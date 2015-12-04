# @Author: Marcin Sucharski

.eqv SYSCALL_FILE_OPEN 13
.eqv SYSCALL_FILE_READ 14
.eqv SYSCALL_FILE_WRITE 15
.eqv SYSCALL_FILE_CLOSE 16
.eqv SYSCALL_EXIT 10
.eqv SYSCALL_PRINT_STRING 4
.eqv SYSCALL_READ_INT 5
.eqv SYSCALL_READ_STRING 8
.eqv SYSCALL_SBRK 9

.eqv BMP_HEADER_SIZE 54
.eqv FILENAME_BUFFER 64

.data
	ask_filename: 		.asciiz "Enter filename: "
	ask_width: 		.asciiz "Enter destination width: "
	ask_height: 		.asciiz "Enter destination height: "
	output_filename: 	.asciiz "output.bmp"

	file_open_err: .asciiz "Unable to open file"
	file_read_err: .asciiz "Error occurred while reading file"
	img_scale_err: .asciiz "Error occurred while scalling image"
	file_save_err: .asciiz "Error occurred while saving file"

	header: 	.space BMP_HEADER_SIZE
	zero_bytes: 	.byte 0, 0, 0, 0
	filename: 	.space FILENAME_BUFFER

.text
.globl main
main:
	# get filename
	li $v0, SYSCALL_PRINT_STRING
	la $a0, ask_filename
	syscall # print message
	li $v0, SYSCALL_READ_STRING
	la $a0, filename
	li $a1, FILENAME_BUFFER
	syscall # reads filename
	
	# get length of string
	la $a0, filename
	jal strlen
	# remove endling
	la $t0, filename 
	addu $t0, $t0, $v0 # address of endline + 1
	sb $zero, -1($t0) # set endline to null character
	
	# get width
	li $v0, SYSCALL_PRINT_STRING
	la $a0, ask_width
	syscall # ask for width
	li $v0, SYSCALL_READ_INT
	syscall
	move $s3, $v0 # save dest width in $s3
	
	# get height
	li $v0, SYSCALL_PRINT_STRING
	la $a0, ask_height
	syscall # ask for height
	li $v0, SYSCALL_READ_INT
	syscall # get height
	move $s4, $v0 # save dest height in $s4
	
	# open input file
	li $v0, SYSCALL_FILE_OPEN # syscall code
	la $a0, filename # pointer to filename
	li $a1, 0 # read-only file
	syscall
	blt $v0, $zero, main_err_open_file # check file descriptor
	move $s0, $v0 # save file descriptor
	
	# read bmp header
	move $a0, $s0 # file descriptor
	li $v0, SYSCALL_FILE_READ # syscall code
	la $a1, header # pointer to buffer
	li $a2, BMP_HEADER_SIZE # size of buffer
	syscall
	bne $v0, BMP_HEADER_SIZE, main_err_reading_file
	
	# ignore rest of headers
	ulw $t0, header+10 # load offset of image data
	subu $a1, $t0, BMP_HEADER_SIZE # number of bytes to ignore
	# $a0 already contains file descriptor
	jal file_ignore # ignore bytes
	bne $v0, $zero, main_err_reading_file # handle error
	
	# load and calculate basic image info
	ulw $s1, header+18 # load image width
	ulw $s2, header+22 # load image height
	
	# load image data
	move $a0, $s0 # file descriptor
	move $a1, $s1 # image width
	move $a2, $s2 # image height
	jal image_load
	beq $v0, $zero, main_err_reading_file # handle error
	move $s5, $v0 # save image date pointer in $s5
	
	# scale image
	move $a0, $s1 # source width
	move $a1, $s2 # source height
	move $a2, $s3 # dest width
	move $a3, $s4 # dest height
	move $t0, $s5 # image date
	jal image_scale
	beq $v0, $zero, main_err_scale_image # handle error
	move $s6, $v0 # save pointer to scaled image
	
	# save image
	la $a0, output_filename # set output file path
	move $a1, $v0 # set data pointer
	move $a2, $s3 # dest image width
	move $a3, $s4 # dest image height
	la $t0, header # pointer to header
	jal image_save
	bne $v0, $zero, main_err_save_file # handle error

main_exit:
	li $v0, SYSCALL_EXIT
	syscall
main_err_open_file:
	li $v0, SYSCALL_PRINT_STRING
	la $a0, file_open_err
	syscall
	j main_exit
main_err_reading_file:
	li $v0, SYSCALL_PRINT_STRING
	la $a0, file_read_err
	syscall
	j main_exit
main_err_scale_image:
	li $v0, SYSCALL_PRINT_STRING
	la $a0, img_scale_err
	j main_exit
main_err_save_file:
	li $v0, SYSCALL_PRINT_STRING
	la $a0, file_save_err
	j main_exit


# Returns length of string
#
# Arguments:
# $a0 - pointer to string
#
# Results:
# $v0 - length of string
strlen:
	move $v0, $a0 # store start of string in $v0
	li $t1, 1 # helper value
strlen_loop:
	lb $t0, ($a0) # load character
	addu $a0, $a0, $t1 # increase string pointer
	bne $t0, $zero, strlen_loop # check for null character
	subu $v0, $a0, $v0 # number of characters + 1
	subu $v0, $v0, $t1 # fix result
	jr $ra
	

# Ignores specified number of bytes in file
# 
# Arguments:
# $a0 - file descriptor
# $a1 - number of bytes
#
# Results:
# $v0 - zero upon success, non-zero value otherwise
file_ignore:
	move $a2, $a1 # save number of bytes
	subu $sp, $sp, $a1 # allocate buffer on stack
	li $v0, SYSCALL_FILE_READ # syscall code
	# $a0 already contains file descriptor
	move $a1, $sp # $sp points to beginning of buffer
	# $a2 already contains number of bytes
	syscall
	bne $v0, $a2, file_ignore_io_error # invalid number of bytes read
	move $v0, $zero # set success error code
file_ignore_exit:
	jr $ra # return
file_ignore_io_error:
	li $v0, -1 # set error code
	j file_ignore_exit


# Loads image data from file
#
# Arguments;
# $a0 - file descriptor
# $a1 - image width
# $a2 - image height
#
# Result:
# $v0 - pointer to data or null in case of error
image_load:
	# prolog
	subu $sp, $sp, 32
	sw $ra, ($sp)
	sw $s0, 4($sp)
	sw $s1, 8($sp)
	sw $s2, 12($sp)
	sw $s3, 16($sp)
	sw $s4, 20($sp)
	sw $s5, 24($sp)
	sw $s6, 28($sp)
	
	move $s5, $a0 # save file descriptor
	move $s0, $a1 # save width
	move $s1, $a2 # save height
	
	# calculate row complement
	mulu $s2, $s0, 3 # number of bytes per row
	and $t0, $s2, 0x3 # remainder of division by 4
	li $t1, 4
	subu $t0, $t1, $t0 # number of unused bytes in each row
	and $s3, $t0, 0x3 # ignore 4-byte complement
	addu $s6, $s2, $s3 # size of row + complement
	
	# allocate buffer
	mulu $a0, $s2, $s1 # size of image
	addu $a0, $a0, 4 # additional 4 bytes for easier loading (row complement)
	li $v0, SYSCALL_SBRK
	syscall
	beq $v0, $zero, image_load_err # handle error
	move $s4, $v0 # save pointer to memory
	
	move $t1, $s4 # write position in buffer
	move $t0, $s1 # loop counter
image_load_loop: # for each row
	li $v0, SYSCALL_FILE_READ
	move $a0, $s5 # file descriptor
	move $a1, $t1 # output buffer
	move $a2, $s6 # size
	syscall
	bne $v0, $s6, image_load_err # handle error
	addu $t1, $t1, $s2 # add row size without complement to buffer pointer
	subu $t0, $t0, 1 # decrease loop counter
	bgt $t0, $zero, image_load_loop
	
	move $v0, $s4
image_load_exit:
	# epilog
	lw $s6, 28($sp)
	lw $s5, 24($sp)
	lw $s4, 20($sp)
	lw $s3, 16($sp)
	lw $s2, 12($sp)
	lw $s1, 8($sp)
	lw $s0, 4($sp)
	lw $ra, ($sp)
	addu $sp, $sp, 32
	jr $ra
image_load_err:
	# buffer should be freed here, but no such syscall exists
	move $v0, $zero
	j image_load_exit



# Saves image to specified file
#
# Arguments:
# $a0 - pointer to filename
# $a1 - pointer to image data
# $a2 - image width
# $a3 - image height
# $t0 - pointer to loaded image header (will be modified)
#
# Results:
# $v0 - zero upon sucess, non-zero value otherwise
image_save:
	# prolog
	subu $sp, $sp, 32
	sw $ra, ($sp)
	sw $s0, 4($sp)
	sw $s1, 8($sp)
	sw $s2, 12($sp)
	sw $s3, 16($sp)
	sw $s4, 20($sp)
	sw $s5, 24($sp)
	sw $s6, 28($sp)
	
	move $s1, $a1 # pointer to image data
	move $s2, $a2 # image width
	move $s3, $a3 # image height
	move $s4, $t0 # pointer to loaded image header
	
	# open file
	li $v0, SYSCALL_FILE_OPEN
	# $a0 already contains pointer to filename
	li $a1, 1 # open write-only
	move $a2, $zero # unused
	syscall
	blt $v0, $zero, image_save_io_error # handle error
	move $s0, $v0 # save file descriptor
	
	# calculate row complement
	mulu $s5, $s2, 3 # number of bytes per row
	and $t0, $s5, 0x3 # remainder of division by 4
	li $t1, 4
	subu $t0, $t1, $t0 # number of unused bytes in each row
	and $s6, $t0, 0x3 # ignore 4-byte complement
	
	# fix header
	li $t0, BMP_HEADER_SIZE
	addu $t1, $s2, $s6 # size of row with complement
	mulu $t1, $t1, $s3 # number of pixels
	mulu $t1, $t1, 3 # size of image data
	usw $t1, 34($s4) # fix size of image
	addu $t1, $t1, $t0 # size of file
	usw $t1, 2($s4) # fix whole file size
	usw $t0, 8($s4) # fix offset
	li $t0, 40 # size of DIB header
	usw $t0, 14($s4) # fix size of DIB header
	usw $s2, 18($s4) # fix image width
	usw $s3, 22($s4) # fix image height
	
	# write header
	li $v0, SYSCALL_FILE_WRITE
	move $a0, $s0 # file descriptor
	move $a1, $s4 # pointert to header
	li $a2, BMP_HEADER_SIZE # number of bytes to write
	syscall
	bne $v0, BMP_HEADER_SIZE, image_save_io_error # handle error
	
	# prepare loop
	move $t1, $s1 # current positoin in image data
	move $t0, $s3 # loop counter
image_save_loop: # per row
	# save row
	li $v0, SYSCALL_FILE_WRITE
	# $a0 already contains file descriptor
	move $a1, $t1 # pointer to buffer
	move $a2, $s5 # size of buffer
	syscall
	bne $v0, $s5, image_save_io_error # handle error
	
	beq $s6, $zero, image_save_ignore_complement
	# save complement bytes
	li $v0, SYSCALL_FILE_WRITE
	# $a0 already conatins file descriptor
	la $a1, zero_bytes # pointer to zero bytes
	move $a2, $s6 # number of bytes to write
	syscall
	bne $v0, $s6, image_save_io_error # handle error
	
image_save_ignore_complement:
	subu $t0, $t0, 1 # decrease loop counter
	addu $t1, $t1, $s5 # add row size to position in image data
	bne $t0, $zero, image_save_loop # check loop condition
	
	# close file
	li $v0, SYSCALL_FILE_CLOSE
	move $a0, $s0 # file descriptor
	syscall
	move $v0, $zero
image_save_exit:	
	# epilog
	lw $s6, 28($sp)
	lw $s5, 24($sp)
	lw $s4, 20($sp)
	lw $s3, 16($sp)
	lw $s2, 12($sp)
	lw $s1, 8($sp)
	lw $s0, 4($sp)
	lw $ra, ($sp)
	jr $ra
image_save_io_error:
	li $v0, -1
	j image_save_exit

# Scales image to specified size
#
# Arguments:
# $a0 - source width
# $a1 - source height
# $a2 - dest width
# $a3 - dest height
# $t0 - pointer to image data
#
# Results:
# $v0 - pointer to scaled image
image_scale:
	# prolog
	subu $sp, $sp, 32
	sw $ra, ($sp)
	sw $s0, 4($sp)
	sw $s1, 8($sp)
	sw $s2, 12($sp)
	sw $s3, 16($sp)
	sw $s4, 20($sp)
	sw $s5, 24($sp)
	sw $s6, 28($sp)
	
	move $s0, $a2 # save dest width
	move $s1, $a3 # save dest height
	move $s2, $a0 # save source width
	move $s3, $a1 # save source height
	move $s4, $t0 # save pointer to data
	
	# allocate output buffer
	li $v0, SYSCALL_SBRK
	mulu $a0, $s0, $s1 # number of pixels in dest image
	mulu $a0, $a0, 3 # number of bytes in dest image
	addu $a0, $a0, 4 # additional 4 bytes for easier writing to memory
	syscall
	beq $v0, $zero, image_scale_err # handle error
	move $s5, $v0 # save pointer to buffer
	
	mulu $s6, $s2, 3 # row size
	
	move $t2, $s5 # write pointer
	move $t0, $zero # row index
image_scale_row_loop: # loop for eeach row
	# get row index in source image
	mulu $t3, $t0, $s3
	divu $t3, $t3, $s1 # row index in source image
	
	move $t1, $zero # column index
image_scale_pixel_loop: # loop for each pixel in row
	# get column index in source image
	mulu $t4, $t1, $s2
	divu $t4, $t4, $s0 # column index in source image
	
	# get pixel in source image
	mulu $t5, $t3, $s6 # row offset
	mulu $t6, $t4, 3 # pixel offset in row
	addu $t5, $t5, $t6 # offset
	
	addu $t6, $s4, $t5 # pointer to pixel
	ulw $t7, ($t6) # load word with pixel
	usw $t7, ($t2) # save word with pixel (additional byte will be ignored)
	
	addu $t2, $t2, 3 # increment write pointer
	addu $t1, $t1, 1 # increment column index
	blt $t1, $s0, image_scale_pixel_loop
	
	addu $t0, $t0, 1 # increment row index
	blt $t0, $s1, image_scale_row_loop
	
	move $v0, $s5 # set result
image_scale_exit:
	# epilog
	lw $s6, 28($sp)
	lw $s5, 24($sp)
	lw $s4, 20($sp)
	lw $s3, 16($sp)
	lw $s2, 12($sp)
	lw $s1, 8($sp)
	lw $s0, 4($sp)
	lw $ra, ($sp)
	addu $sp, $sp, 48
	jr $ra
image_scale_err:
	# allocated memory on heap should be freed here, but there is no such syscall
	move $v0, $zero
	j image_scale_exit
