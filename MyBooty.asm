* ===========================================================================
*
* Processor:	    68332
* Assembler:		AS32 Free CPU32 Assembler by Scott Howard
*
* NOTE The S-record file needs to be replaced to have the correct start
* address in SRAM which is 0x5000
* Replace the S7 record: S705205C00007E with this S9 record: S9035000AC
* or use MyBooty.cmd script to assemble and produce the correct S-record file
* all in one go.
*
* ===========================================================================
* ===========================================================================
*
*	MyBooty Version 1
*	7-May-2010
*	By Sophie Dexter
* 	With help and lots of information from Dilemma
*	Also using bits and pieces from General Failure and Patrik Servin
*
* WARNING: Use at your own risk, sadly this software comes with no guarantees
* This software is provided 'free' and in good faith, but the author does not
* accept liability for any damage arising from its use.
*
* ===========================================================================
*
* This is 'My Cheeky Little Turbo-Charged Bootloader' for T5.5 and T5.2 ECUs
*
* 'Universal' use it with all T5 ECU types, T5.2, T5.5, 16 MHz and 20 Mhz
*
* It does everything the other Bootloaders do and adds a command, C9, which
* replies with the 'Start Address of FLASH' and the FLASH chip's 'ID'
*
* Did I mention that it works with AMD 29F010 chips too? Well it does :-)
* It also recognises Atmel 29C512/010 chips but it can't program them :-(
*
* 'Turbo-Charged' - it does everything faster than other bootloaders.
* 
* 'little' - it does more yet is half the size (it loads more quickly too :-)
*
* 'Cheeky' - well, that's for me to know and you to find out ;-)
*
* ===========================================================================
*
* When I started to write this it was quite easy to follow...
*
* Then I realised that although it was easy to understand it could be more
* efficient...
*
* Now it is quite efficient, but hard to understand so, here are a few
* pointers for anyone that is interested:
*
* I found these websites helpful, though probably didn't follow all of their
* advice:
*
* http://68k.hax.com/
* http://www.easy68k.com/paulrsm/
* http://www.virtualdub.org/blog/pivot/entry.php?id=84
*
* Backwards :-)
* =============
* I noticed that some things are back to front to the way I expected them to
* be so I decided to go with the trend. Consequently many things count down to
* zero:
* 
* 		subq.l	#1,d0
* 		beq.w	somewhere
*
* Has to be quicker than:
*
* 		addq.l	#1,d0
* 		cmp.l	d0,d1
*	 	beq.w 	somewhere
* 
* and it makes for smaller code - less instructions and uses fewer registers
*
* However, I often count down from a number say 10 bytes to program, but
* the address starts at '0' so you will see things like:
*
*		move.b	d4,-1(a5,d2.l)		* The -1 makes up for the difference
*
* Has She Gone Loopy? - nop(e)
* ============================
*
* I have used delay loops that look like this:
*
*		moveq 	#Count_6us,d1
* Verify_6us_Delay:
*		nop
*		dbeq	d1,Verify_6us_Delay
*
* So, what's that 'nop' instruction doing there, it doesn't do anything does
* it? Well, the 68332 processor has a special 'loop mode' but for it to work
* there has to be one instruction in the loop. The 'loop mode' is much
* faster and is discussed on one of the websites I listed above. NOTE that
* this type of loop actually counts down to -1! so set the loop count one
* lower than you need :-)
*
* So what you say, if we want a delay, it doesn't matter how fast surely -
* it's a delay for a certain time. Of course, but by doing it this way it's
* possible to control the delay time more precisely. I timed the loop with
* and without the 'nop' instruction. With the 'nop' each loop takes ~ 0.48
* microseconds but about 1.3 microseconds without it - over 2.5 times longer.
* The advantage I see is that that faster loop can get closer to the ideal
* time. So I decided to sacrifice a little bit of code size for a precision.
*
* (How did I time this with my watch? Simple, I created two loops, one inside
* the other. The outside loop repeated 10,000 times. I changed the inside
* loop to repeat 3,000 times and then 8,000 times and timed how long each
* version took to get to the end. Simply take the difference in times and
* divide by 50,000,000 to get the answer (10,000 * 5,000).
*
* Registers :-)
* =============
* If something is used often then it is quicker and smaller to store that
* value in a register. E.g. the watchdog has to be reset often so I have
* reserved a6 for the watchdog address and d6 and d7 for the reset values for
* the watchdog (which also conveniently double up for part of the AMD 29C010
* programming sequences. a5 is also reserved for the address of the start of
* FLASH
*
* Reserved Registers:
* ===================
*
* If you want to modify this code be aware that I use these registers
* and expect them to always have the correct value in them.
*
*	d6 - 0x5555 used for resetting the watchdog - also for AMD 29C commands
*	d7 - 0xAAAA used for resetting the watchdog - also for AMD 29C commands
*
*	a5 - Flash_Start_Address either 0x40000 for T5.5 or 0x60000 for T5.2
*	a6 - Watchdog SWSR in SIM address
*
* Register Use In General:
* ========================
*
*	d0	(and sometimes d1) used for checking various things out, e.g. FLASH
* 		type, programmed data value etc
*		often used to return a pass/fail result from a subroutine
*	d1	often used as a counter in delay loops
*		used for AMD 29F010 FLASH programming command (no delay counter)
*	d2	often used as a counter of howm bytes to program/erase etc
* 	d3	often used for 28F FLASH programming/erase sequence commands
* 	d4	often used for 28F FLASH verification sequence commands
*	d5	often used for number of FLASH retry or timeout checking
*
*	a0	exclusively used for CAN receive buffer, but value changes
*	a1	exclusively used for CAN transmit buffer, but value changes
*	a2	often used for CAN device addresses
*	a3	often used for CAN device addresses
*		often used for the FLASHWrite buffer address
*	a4	often used for the first address of FLASH to program
*		(use together with d2 to get the actual address)
*
* Registers may be used for other purposes as well, this is just a rough
* guide to how and when I have used them !!!
*
* ===========================================================================
*
* The CAN Message 'Commands':
* ===========================
*
* All messages sent to the T5 ECU have an id of 0x005, all messages from the
* the T5 ECU have and id of 0x00C. Messages always contain 8 bytes of data.
*
*	C0 - Erase the FLASH chips
*	C2 - Exit the Bootloader and restart the T5 ECU
*	C3 - Get the last Address of the FLASH chips
*	C7 - Read the FLASH Contents - use to 'dump' FLASH contents
*	C8 - Calculate the Flash Checksum - use to check programming was OK
*	C9 - Start address and FLASH chip type - use to find out if T5.5 or T5.2
*	A5 - Tell bootloader to expect some bytes - use for 'reFLASHing'
*	01-7F - send up to 7 bytes at a time - to be FLASHed
*
* Any other message is ignored, but the T5 ECU lets you know that it didn't
* understand the message by responding like this:
*
*	xx,09,08,08,08,08,08,08
*
*	xx is the command that the T5 doesn't recognise repeated back in the reply
*	09 means that the command wasn't recognised
*	08,08,08,08,08,08 is just to make the message length up to 8 bytes
*
* In a bit more detail:
*
*	C0,00,00,00,00,00,00,00	- Erase the FLASH chips
*	replies with:
*	C0,
*	   00,					- success, FLASH was erased
*		  08,08,08,08,08,08
*	C0,
*      cc,					- reply code
*         aa,bb,cc,dd		- 0xaabbccdd address that failed
*					 ,08,08
*
*	0xaabbccdd is the address that failed to erase
*			   only meaningful for 01 or 02 'cc' codes (see below)
*			   there will be a random value here with other codes
*
*	'cc' can be
*	01 - failure, unable to erase FLASH chips
*	02 - failure, cannot write zeroes to 28F512/010 chips only
*	03 - Failure, unrecognised FLASH chips, unknown make
*	04 - failure, unrecognised Intel FLASH chips
*	05 - failure, unrecognised AMD FLASH chips
*	06 - failure, unrecognised CSI/Catalyst FLASH chips
*	07 - Atmel 29C010/512 chips (which don't need to be erased)
* ---------------------------------------------------------------------------
*	C2,00,00,00,00,00,00,00	- Exit the Bootloader and restart the T5 ECU
*	replies with:
*	C2,00,08,08,08,08,08,08
*	and then the T5 ECU restarts...
* ---------------------------------------------------------------------------
*	C3,00,00,00,00,00,00,00	- Get the last Address of the FLASH chips
*	replies with:
*	C3,
*      00,					- Success
*         00,07,FF,FF		- The last address is always 0x7FFFF
*                    ,08,08	- 
* ---------------------------------------------------------------------------
*	C7,aa,bb,cc,dd,00,00,00	- Read the FLASH Contents at address 0xaabbccdd
*	replies with:
*	C7,
*      00,					- Success
*         dd,				- data byte at address 
*            dd,			- data byte at (address - 1)
*               dd,			- data byte at (address - 2)
*                  dd,		- data byte at (address - 3)
*                     dd,	- data byte at (address - 4)
*                        dd	- data byte at (address - 5)
*	Use this command (repeatedly and with different addresses) to 'dump' the
*	FLASH contents (before re-FLASHing).
*	Be careful using the C7 command, using 'bad' address values will make the
*	T5 ECU restart!
*	Values between 0x40005 and 0x7FFF are OK for T5.5
*	Values between 0x60005 and 0x7FFF are OK for T5.5
* ---------------------------------------------------------------------------
*	C8,00,00,00,00,00,00,00	- Calculate the Flash Checksum
*	Replies with:
*	C8,01,08,08,08,08,08,08 - Failure, the checksum doesn't match
*	or
*	C8,
*      00,					- Success
*         ss,ss,ss,ss,		- The Checksum value
*                     08,08
* ---------------------------------------------------------------------------
*	C9,00,00,00,00,00,00,00	- Get start address and FLASH chip type
*	Replies with:
*	C9,
*      00,					- Success
*         aa,bb,cc,dd,		- 0xaabbccdd is the start address
*                     mm,	- FLASH chip Manufaturer code
*                        tt - FLASH chip Type code
*
*	0xaabbccdd is the start address this will either be
*	0x00040000 for a T5.5 ECU or
*	0x00060000 for a t5.2 ECU
*
*	mm = Manufacturer id. These can be:
*	0x89 - Intel
*	0x31 - CSI/CAT
*	0x01 - AMD
*	0x1F - Atmel
*
*	tt = Device id. These can be:
*	0xB8 - Intel _or_ CSI 28F512 (Fiited by Saab in T5.2)
*	0xB4 - Intel _or_ CSI 28F010 (Fitted by Saab in T5.5)
*	0x25 - AMD 28F512 (Fiited by Saab in T5.2)
*	0xA7 - AMD 28F010 (Fitted by Saab in T5.5)
*	0x20 - AMD 29F010 (Some people have put these in their T5.5)
*	0x5D - Atmel 29C512 (Some people may have put these in their T5.2)
*	0xD5 - Atmel 29C010 (Some people have put these in their T5.5)
* ---------------------------------------------------------------------------
*	A5,aa,bb,cc,dd,nn,00,00	- Address and Count of bytes to send to FLASH
*	   aa,bb,cc,dd,			- 0xaabbccdd address to start programming from
*				   nn		- 0xnn number of bytes to follow for programming
*
*	Replies with:
*	A5,00,08,08,08,08,08,08
*
*	0xaabbccdd is the start address this can be anything from
*	0x00040000 for a T5.5 ECU or
*	0x00060000 for a t5.2 ECU
*	to
*	0x0007FFFF - the last address in FLASH
*
*	0xnn is the number of bytes to program, can be from 0x01 to 0x7F
*
*	Be careful using the A5 command:
*	Make sure that 0xaabbccdd + 0xnn isn't more than 0x0007FFFF
* ---------------------------------------------------------------------------
*	01-7F - send up to 7 bytes of data at a time to be FLASHed
*	nn,dd,dd,dd,dd,dd,dd,dd
*
*	0xnn usually starts at 0x00 and goes up in 7's e.g 0x07, 0x0E, 0x15, 0x1C
*	it is an 'offset' into the count of bytes being sent for FLASHing
*
*	dd,dd,dd,dd,dd,dd,dd are (up to) 7 bytes of data for FLASHing
*	When the correct number of bytes have been sent then they are all
*	programmed into the FLASH chips.
*
*	Replies with:
*	nn,cc,08,08,08,08,08,08
*	'cc' can be
*	00 - success, bytes were received or FLASH was programmed OK
*	01 - failure, unable to program FLASH chips with the data bytes
* ===========================================================================
* ===========================================================================

* Some 'equates' used in the program code:

Watchdog_Address	EQU $FFFA26
CAN_Address1		EQU $F007FF
CAN_Address2		EQU $F00800
Last_Address_Of_T5	EQU	$7FFFF
Intel_Make_Id		EQU	$89
AMD_Make_Id			EQU $01
CSI_Make_Id			EQU $31
Atmel_Make_Id		EQU $1F
Intel_28F512_Id		EQU	$B8		* Also CSI
Intel_28F010_Id		EQU $B4		* Also CSI
AMD_28F512_Id		EQU $25
AMD_28F010_Id		EQU	$A7
AMD_29F010_Id		EQU	$20
Atmel_29C512_Id		EQU	$5D
Atmel_29C010_Id		EQU	$D5
Count_10ms			EQU	22000	* 22,001 loops x 0.48 = 10.56 ms
Count_10us			EQU	21		* 22 loops x 0.48 = 10.56 us
Count_6us			EQU 12		* 13 loops x 0.48 = 6.24 us

	org 	$5000


* =============== M A I N _ P R O G R A M ===================================
* ===========================================================================
* =============== My_Booty ==================================================
* ===========================================================================

My_Booty:
		jsr		(Preparation).w
		jsr		(Bootloader_Loop).w
		addq.l	#4,a5		* FLASH Start Address
		jmp		(a5)		* Restart ECU by jumping to start vector address

* ===========================================================================
* =============== End of My_Booty ===========================================
* ===========================================================================


* =============== S U B	R O U T	I N E =======================================
* ===========================================================================
* =============== Preparation ===============================================
* ===========================================================================

Preparation:

* Set frequency to 16 MHz (actually 16.78 MHz) for all T5 ECU types
* The main reason for doing this is to make the delay loops the same
* so that 16 and 20 Mhz ECUs will work with the same values

		andi.b	#$3F,($FFFA04).l
		ori.b	#$3F,($FFFA04).l	* multiply by 256 = 8.388 MHz
Synthesiser_Lock_Flag:
		move.b	($FFFA05).l,d0
		lsr.b	#3,d0
		andi.b	#1,d0
		beq.b	Synthesiser_Lock_Flag
		ori.b	#$40,($FFFA04).l	* multiply by 512 = 16.78 MHz

* Setup chip select modes
		
		move.w	#$3030,($FFFA52).l * Synchronous mode selected,	Upper Byte to CSOR1
		move.w	#$5030,($FFFA56).l * Synchronous mode selected,	Lower Byte to CSOR2

* PORTQS latches I/O data. Writes drive	pins defined as outputs. Reads return
* data present on the pins.
* To avoid driving undefined data, first write a byte to PORTQS, then
* configure DDRQS.

		andi.w	#$FFBF,($FFFC14).l	* PQS Data Register (PORTQS)
		ori.w	#$10,($FFFC14).l	* PQS Data Register (PORTQS)

		andi.b	#$40,($FFFC16).l	* PQS Data Direction Register (DDRQS)
		ori.w	#$40,($FFFC16).l	* PQS Data Direction Register (DDRQS)

		andi.w	#$FFDF,($FFFC16).l	* PQS Data Direction Register (DDRQS)
		ori.w	#$10,($FFFC16).l	* PQS Data Direction Register (DDRQS)

* Work out the first address of FLASH from the Chip-Select Register
* This will be 0x40000 for T5.5 or 0x60000 for T5.2
		
		move.w	($FFFA48).l,d0	* Chip-Select Base Address Register Boot ROM
		andi.l	#$FFF8,d0
		lsl.l	#8,d0
		move.l	d0,a5			* FLASH_Start_Address held in a5 register

* Store the Watchdog address in a6 and reset values in d6 and d7 registers

		movea.l	#Watchdog_Address,a6
		move.w	#$5555,d6
		move.w	#$AAAA,d7

		rts
*============================================================================
* =============== End of Preparation ========================================
*============================================================================


* =============== S U B	R O U T	I N E =======================================
* ===========================================================================
* =============== Bootloader_Loop ===========================================
* ===========================================================================

Bootloader_Loop:
		jsr		(Wait_For_CAN_Message).w
		movea.l	#CanRxBuffer,a0
		movea.l	#CanTxBuffer,a1
		move.b	(a0),d0				* store message type to check against
		move.b	d0,(a1)+			* Copy message type to CAN buffer
* ---------------------------------------------------------------------------
		move.b	#9,(a1)+			* Code 9 - unrecognised command
		move.l	#$08080808,(a1)+	* CanTxBuffer2-5
		move.w	#$0808,(a1)			* CanTxBuffer6-7
		subq.l	#5,a1				* a1 points to CanTxBuffer1 again 'code'
* ---------------------------------------------------------------------------
		cmpi.b	#$A5,d0				* A5 command - address and count of Bytes
		beq.w	A5_Command
* ---------------------------------------------------------------------------
		cmpi.b	#$7F,d0				* 0x00-0x7F upto 7 bytes of FLASH data
		bls.w	Data_Command		* bls - less than or equal to 0x7F
* ---------------------------------------------------------------------------
		cmpi.b	#$C0,d0				* C0 command - erase flash chips
		beq.w	C0_Command
* ---------------------------------------------------------------------------
		cmpi.b	#$C2,d0				* C2 command - Exit bootloader
		beq.w	C2_Command
* ---------------------------------------------------------------------------
		cmpi.b	#$C3,d0				* C3 command - Get last address of FLASH
		beq.w	C3_Command
* ---------------------------------------------------------------------------
		cmpi.b	#$C7,d0				* C7 command - Read 6 bytes of FLASH
		beq.w	C7_Command
* ---------------------------------------------------------------------------
		cmpi.b	#$C8,d0				* C8 command - Calculate FLASH Checksum
		beq.w	C8_Command
* ---------------------------------------------------------------------------
		cmpi.b	#$C9,d0				* C9 command - Get FLASH Id
		beq.w	C9_Command

* ===========================================================================
* =============== Send_CAN_Response =========================================
* ===========================================================================
* Sends the CAN message replies
*
* Checks to see if the received message was 'C2' and exits if it was.
* Otherwise goes back to the start and waits for another CAN message
* ===========================================================================

Send_CAN_Response:
		jsr		(Send_A_CAN_Message).w
		cmpi.b	#$C2,(a1)			* a1 = CanTxBuffer0, $C2 - exit
		bne.b	Bootloader_Loop		* Then return to start
		rts		* else,	we were	signalled to quit the main loop	by C2 command
* ===========================================================================
* =============== End of Bootloader_Loop ====================================
* ===========================================================================


* ===========================================================================
* =============== A5 command - Address and Count of bytes to send to FLASH ==
* ===========================================================================

A5_Command:
		move.l	(a0)+,d0				* a0 = CanRxBuffer0
		lsl.l	#8,d0		* Remove A5 code by shifting left 8 times, d0 now
*							  contains most of the FLASH address
		or.b	(a0)+,d0				* Get low byte of FLASH address
		movea.l	d0,a2					* FLASH address now in a2 register	
		move.l	a2,(FlashAddress).w		* Store a copy of the FLASH address
		move.b	(a0),(FlashLength).w	* FLASH bytes to follow

		clr.b	(a1)		* 0 - OK, CanTxBuffer1
		bra.w	Send_CAN_Response
* ===========================================================================

* ===========================================================================
* =============== 01-7F commands - Data Bytes for programmng FLASH ==========
* ===========================================================================

Data_Command:
		movea.l	#FlashBuffer,a2		* Buffer for storing bytes for FLASH
		moveq	#1,d0				* Count of bytes read from CAN buffer
		clr.l	d1
		move.b	(a0),d1				* Offset into FlashBuffer
		move.b	(FlashLength).w,d2	* Total number of bytes to put in buffer
Copy_Byte:
		move.b	(a0,d0.l),(a2,d1.l)	* Copy from CANbuffer to Flash Buffer
		addq.b	#1,d1
		cmp.b	d2,d1				* Has the Flash buffer been filled
		beq.b	Do_Programming		* Program the flash if it is
		cmpi.b	#7,d0				* Was this the last Byte in CAN Buffer
		beq.b	Emptied_CAN
		addq.b	#1,d0
		bra.b	Copy_Byte
* ---------------------------------------------------------------------------
Do_Programming:
		jsr		(Flash_Programming).w
		move.b	d0,(a1)+
		beq.w	Send_CAN_Response
* ---------------------------------------------------------------------------
		move.l	d4,(a1)					* Address that failed
		andi.w	#$FFBF,($FFFC14).l		* Turn FLASH power off
		bra.w	Send_CAN_Response
* ---------------------------------------------------------------------------
Emptied_CAN:
		clr.b	(a1)
		bra.w	Send_CAN_Response
* ===========================================================================


* ===========================================================================
* =============== C0 command - Erase the FLASH Chips ========================
* ===========================================================================

C0_Command:
		jsr		(Get_FLASH_Id_Bytes).w
		jsr		(Erase_FLASH_Chips).w
		move.b	d0,(a1)+
		beq.w	Send_CAN_Response
* ---------------------------------------------------------------------------
		move.l	d2,(a1)					* Address that failed
		andi.w	#$FFBF,($FFFC14).l		* Turn FLASH power off
		bra.w	Send_CAN_Response
* ===========================================================================

* ===========================================================================
* =============== C2 command - Exit Boot Loader and restart T5 ==============
* ===========================================================================

C2_Command:
		andi.w	#$FFBF,($FFFC14).l		* Turn FLASH power off
		clr.b	(a1)
		bra.w	Send_CAN_Response
* ===========================================================================

* ===========================================================================
* =============== C3 command - Return last Address of FLASH - 0x7FFFF =======
* ===========================================================================

C3_Command:
		clr.b	(a1)+				* 0 - OK, CanTxBuffer1
		move.l	#Last_Address_Of_T5,(a1)	* CanTxBuffer2-5
		bra.w	Send_CAN_Response
* ---------------------------------------------------------------------------

* ===========================================================================
* =============== C7 command - Read FLASH Contents ==========================
* ===========================================================================
*
*	d0 - Used to calculate FLASH Address from the received CAN Message
*
*	a1 - used for counting CAN Transmit buffer position
*	a2 - used for counting FLASH address position
* ===========================================================================

C7_Command:
		move.l	(a0)+,d0			* Get top three bytes of address
		lsl.l	#8,d0				* Rotate to get rid of C7 command
		or.b	(a0),d0				* 'or' to add in the low byte
		movea.l	d0,a2
		clr.b	(a1)+				* O - OK, CanTxBuffer1
		move.b	(a2),(a1)+			* CanTxBuffer2
		move.b	-(a2),(a1)+			* CanTxBuffer3
		move.b	-(a2),(a1)+			* CanTxBuffer4
		move.b	-(a2),(a1)+			* CanTxBuffer5
		move.b	-(a2),(a1)+			* CanTxBuffer6
		move.b	-(a2),(a1)			* CanTxBuffer7
		bra.w	Send_CAN_Response
* ===========================================================================

* ===========================================================================
* =============== C8 command - Calculate FLASH Checksum =====================
* ===========================================================================

C8_Command:
		jsr		(Get_Checksum).w
		bra.w	Send_CAN_Response
* ===========================================================================

* ===========================================================================
* =============== C9 command - Get FLASH Id =================================
* ===========================================================================
* NEW C9 GET FLASH id COMMAND, not present in other bootloaders
*
* C9 uses Get_FLASH_Id_Bytes which puts the FLASH id bytes into
* FLASH_Make and FLASH_Type addresses
*
*	a1 - used for counting CAN Transmit buffer position
*	a5 -  - used for Flash_Start_Address (always there)
*
* ===========================================================================

C9_Command:
		jsr		(Get_FLASH_Id_Bytes).w
		clr.b	(a1)+					* 0 - OK, CANTxBuffer1
		move.l	a5,(a1)+				* FLASH start address CANTxBuffer2-5
		move.b	(FLASH_Make).w,(a1)+	* Manufacturer Id in CANTxBuffer6
		move.b	(FLASH_Type).w,(a1)		* Device Id in CANTxBuffer7
		bra.w	Send_CAN_Response		* sends FLASH id
* ===========================================================================


* =============== S U B	R O U T	I N E =======================================
* ===========================================================================
* =============== Wait_For_CAN_Message ======================================
* ===========================================================================
*
* This is a super sripped down version of the same code in the T5 BIN file
* I don't know what it does exactly I just took bits out until it stopped
* working - then put the last bit back in again to make it work :-)
*
*	d0 - used for checking CAN status and a counter for moving data
*	d1 - Stores a copy of the Status Register (sr) while the interrupt is off
* 
*	a0 - CAN Receive Buffer address
*	a2 - CAN instruction address
*	a3 - CAN data byte address
*	a6 - Watchdog SWSR in SIM address
*
* ===========================================================================

Wait_For_CAN_Message:
		movea.l	#CanRxBuffer,a0
		movea.l	#CAN_Address1,a2
		movea.l	#CAN_Address2,a3
* ---------------------------------------------------------------------------
Check_CAN_Loop:
		move	sr,d1				* store status register
		ori		#$700,sr			* disable interrupt
		move.b	#2,(a2)				* 
		tst.b	(a3)				* dummy read of CAN chip?
* ---------------------------------------------------------------------------
Wait_For_Read_Ready:
		move.b	#$12,(a2)			* 
		btst.b	#0,(a3)
		beq.b	Wait_For_Read_Ready
* ---------------------------------------------------------------------------
		move.b	#$13,(a2)			* 
		btst.b	#6,(a3)
		bne.b	Read_CAN_Message	* Branch to read CAN message
* ---------------------------------------------------------------------------
* Could be waiting a long time for a CAN message so re-enable interrupt in
* case there is one (I have no idea who or what can interrupt)
		move	d1,sr				* re-enable interrupt
* Reset_Software_Watchdog
		move.w	d6,(a6)				* Write $5555 to SWSR in SIM
		move.w	d7,(a6)				* Write $AAAA to SWSR in SIM
		bra.b	Check_CAN_Loop
* ---------------------------------------------------------------------------
Read_CAN_Message:
		move.b	#$13,(a2)			* 
		move.b	#8,(a3)				* 
		moveq	#$14,d0
* ---------------------------------------------------------------------------
CAN_Read_Bytes_Loop:
		move.b	d0,(a2)				* 
		move.b	(a3),-$14(a0,d0.w)
		addq.b	#1,d0
		cmpi.b	#$1B,d0				* 0x14 + 0x07 = 0x1B
		bls.b	CAN_Read_Bytes_Loop
* ---------------------------------------------------------------------------
Wait_For_Read_Done:
		move.b	#$12,(a2)			* 
		btst.b	#0,(a3)
		beq.b	Wait_For_Read_Done
* ---------------------------------------------------------------------------
		move.b	#$13,(a2)			* 
		btst.b	#6,(a3)
		bne.b	Read_CAN_Message
* ---------------------------------------------------------------------------
		move	d1,sr				* re-enable interrupt
		rts
* ===========================================================================
* =============== End of Wait_For_CAN_Message ===============================
* ===========================================================================


* =============== S U B	R O U T	I N E =======================================
* ===========================================================================
* =============== Send_A_CAN_Message ========================================
* ===========================================================================
*
* This is a super sripped down version of the same code in the T5 BIN file
* I don't know what it does exactly I just took bits out until it stopped
* working - then put the last bit back in again to make it work :-)
*
*	d0 - used for checking CAN status and a counter for moving data
*	d1 - Stores a copy of the Status Register (sr) while the interrupt is off
* 
*	a1 - CAN Transmit Buffer address
*	a2 - CAN instruction address
*	a3 - CAN data byte address
*
* ===========================================================================

Send_A_CAN_Message:
		movea.l	#CanTxBuffer,a1
		movea.l	#CAN_Address1,a2
		movea.l	#CAN_Address2,a3
* ---------------------------------------------------------------------------
		move	sr,d1				* store status register
		ori		#$700,sr			* disable interrupt
		move.b	#2,(a2)				* 
		tst.b	(a3)				* dummy read of CAN chip?
		move.b	#6,(a2)				* 
		clr.b	(a3)				* 
* ---------------------------------------------------------------------------
Wait_For_Ready_Send:
		move.b	#7,(a2)				* 
		btst.b	#0,(a3)
		beq.b	Wait_For_Ready_Send
* ---------------------------------------------------------------------------
		moveq	#9,d0
* ---------------------------------------------------------------------------
CAN_Send_Bytes_Loop:
		move.b	d0,(a2)				* 
		move.b	-$9(a1,d0.w),(a3)	* 
		addq.b	#1,d0
		cmpi.b	#$10,d0				* 0x09 + 0x07 = 0x10
		bls.b	CAN_Send_Bytes_Loop
* ---------------------------------------------------------------------------
		move.b	#8,(a2)				* 
		move.b	#$88,(a3)			* 
		move.b	#6,(a2)				* 
		move.b	#$80,(a3)			* 
		move	d1,sr				* re-enable interrupt
		rts
* ===========================================================================
* =============== End of Send_A_CAN_Message =================================
* ===========================================================================


* =============== S U B	R O U T	I N E =======================================
* ===========================================================================
* =============== Flash_Programming =========================================
* ===========================================================================
*
*
*	d0 - used to return pass/fail (can also be used for anything temporarily)
*	d1 - used for delay loop counters and testing which FLASH chip type
*	d2 - used to store/countdown the number of bytes to program
*	d3 - used to get the bytes for programming from the FLASH Write Buffer
*	d4 - used to check the programmed byte
*	d5 - used for programming retry counter
*	d6 - 0x5555 used for resetting the watchdog (already there)
*	d7 - 0xAAAA used for resetting the watchdog (already there)
*
*	a0
*	a1
*	a2
*	a3 - is the address of the FLASH_Write_Buffer
*	a4 - is the first FLASH address to program (add to d2)
*	a5 - used for Flash_Start_Address (already there)
*		 either 0x40000 for T5.5 or 0x60000 for T5.2
*	a6 - Watchdog SWSR in SIM address (already there)
*
* ===========================================================================

* ===========================================================================
* =============== First work out what type of FLASH chips are fitted ========
* ===========================================================================

Flash_Programming:
		movea.l	#FlashAddress,a3	* FLASH Write Buffer
		movea.l	(a3),a4			* Where to start programming in FLASH
		cmpa.l	a4,a5				* first, check for flash address range
		bhi.w	Programming_Error
		clr.l	d2
		move.b	4(a3),d2				* Get number of bytes to program
		move.b	(FLASH_Type).w,d1
		cmpi.b	#$20,d1					* AMD 29F010 Device id
		beq.w	Flash_29F
		cmpi.b	#$D5,d1					* Atmel 29C010 Device id
		beq.b	Flash_29C
		cmpi.b	#$5D,d1					* Atmel 29C512 Device id
		beq.b	Flash_29C
		bra.b	Flash_28F				* Assume that they are 28F512/010

		
* ===========================================================================
* =============== Program Atmel 29C010 FLASH chip types =====================
* ===========================================================================
*
* dummy 'placeholder' code for Atmel - always 'fails'
*
* ===========================================================================
	
Flash_29C:
		bra.w	Programming_Error	* Branch back to where Flash_Prog fails

* ===========================================================================
* =============== End of Program Atmel 29C010 FLASH chip types ==============
* ===========================================================================


* ===========================================================================
* =============== Program 28F512/010 FLASH chip types =======================
* ===========================================================================
*
*	d0 - used to get the bytes for programming from the FLASH Write Buffer
*	d1 - used for delay loop counters and testing which FLASH chip type
*	d2 - used to store/countdown the number of bytes to program
*	d3 - used for 28F FLASH program command - 0x40
*	d4 - used for 28F FLASH verify command - 0xC0
*	d5 - used for programming retry counter
*	d6 - 0x5555 used for resetting the watchdog (already there)
*	d7 - 0xAAAA used for resetting the watchdog (already there)
*
*	a0
*	a1
*	a2
*	a3 - is the address of the FLASH_Write_Buffer
*	a4 - is the first FLASH address to program (add to d2)
*	a5 - used for Flash_Start_Address (already there)
*		 either 0x40000 for T5.5 or 0x60000 for T5.2
*	a6 - Watchdog SWSR in SIM address (already there)
*
* note -1 (a4,d2.l) FLASHBuffer because using count of bytes in d2
*
* ===========================================================================

Flash_28F:
		move.b	#$40,d3					* FLASH program command
		move.b	#$C0,d4					* FLASH verify command
Flash_28F_Another:
		move.b	4(a3,d2.l),d0			* Get byte to be programmed into d3
		cmpi.b	#$FF,d0					* Check for FF (should already be FF)
		beq.b	Already_0xFF			* Don't need to program 0xFF
		moveq	#$19,d5					* 25 retries to	program
* ---------------------------------------------------------------------------
Flash_Program_Loop:
		move.b	d3,-1(a4,d2.l)			* FLASH program command
		move.b	d0,-1(a4,d2.l)			* Write	data to	flash address
		moveq 	#Count_10us,d1
Program_10us_Delay:
		nop
		dbeq	d1,Program_10us_Delay
		move.b	d4,-1(a4,d2.l)			* FLASH verify command
		moveq 	#Count_6us,d1
Verify_6us_Delay:
		nop
		dbeq	d1,Verify_6us_Delay
		cmp.b	-1(a4,d2.l),d0			* check that FLASH value is correct
		bne.b	Byte_Not_Programmed
* ---------------------------------------------------------------------------
Already_0xFF:
		subq.l	#1,d2					* Are we done yet?
		bne.b	Flash_28F_Another
		bra.b	Programming_Done
* ---------------------------------------------------------------------------
Byte_Not_Programmed:
		subq.b	#1,d5					* 25 retries to	program
		bne.b	Flash_Program_Loop		* Retry if some retries left		
* ---------------------------------------------------------------------------
Programming_Done:
		clr.w	(a5)			* Put_FLASH_In_Read_Mode
		tst.w	(a5)			* Only needed for AMD, does no harm for Intel
		tst.b	d5				* Error if d5 = 0, - 25 attempts FAILED
		beq.w	Programming_Error
		bra.w	Programming_OK			* Go back to where Flash_Prog OK
* ===========================================================================
* =============== End of Program 28F512/010 FLASH chip types ================
* ===========================================================================


* ===========================================================================
* =============== Program AMD 29F010 FLASH chip types =======================
* ===========================================================================
*
*	d0 - used to select between FLASH chip1 and chip2
*	d1 - Program FLASH Command
*	d2 - count of number of bytes - add to -1(a4) to get address to program
*	d3 - byte to program into FLASH
*	d4 - used for checking that FLASH is programmed
*	d5 - used to check for a programming timeout error 
*	d6 - 0x5555 used for resetting the watchdog - also for AMD 29C commands
*	d7 - 0xAAAA used for resetting the watchdog - also for AMD 29C commands
*
*	a3 - is the address of the FLASH_Write_Buffer
*	a4 - is the first FLASH address to program (add to d2)
*	a5 - used for Flash_Start_Address (already there)
*	a6 - Watchdog SWSR in SIM address (already there)
*
*============================================================================

Flash_29F:
		move.b	#$A0,d1					* Program FLASH Command
		move.l	a4,d0					* work out if chip 1 or 2...
		add.l	d2,d0					* ...by adding address and byte count
		and.l	#1,d0					* ...to see if odd or even 
Flash_29F_Another:
		bchg	#0,d0					* swap between chip 1 and 2 for each
		move.b	4(a3,d2.l),d3			* get a byte to program
		cmpi.b	#$FF,d3					* Check for FF (should already be FF)
		beq.b	Flash_29F_OK			* Don't need to program 0xFF
		move.b	d7,$5555*2(a5,d0.l)		*
		move.b	d6,$2AAA*2(a5,d0.l)		*
		move.b	d1,$5555*2(a5,d0.l)		* Program FLASH sequence
		move.b	d3,-1(a4,d2.l)			* Write	data to	flash address
		and.b	#$80,d3					* Isolate Bit 7 for testing
* Reset_Software_Watchdog
		move.w	d6,(a6)					* Write $5555 to SWSR in SIM
		move.w	d7,(a6)					* Write $AAAA to SWSR in SIM
Flash_29F_Verify:
		move.b	-1(a4,d2.l),d4			* Read back from FLASH
		move.b	d4,d5					* store a copy to test for timeout
		and.b	#$80,d4
		cmp.b	d3,d4					* Test to see if Bit 7 matches
		beq.b	Flash_29F_OK
		btst	#5,d5					* Test to see if timeout
		beq.b	Flash_29F_Verify		* Not timed out so check again
		move.b	-1(a4,d2.l),d4			* Read back from FLASH
		and.b	#$80,d4
		cmp.b	d3,d4					* Test to see if Bit 7 matches
		beq.b	Flash_29F_OK
		move.b	d7,$5555*2(a5,d0.l)		* Programming timed out if here
		move.b	d6,$2AAA*2(a5,d0.l)		* Have to reset FLASH chip when...
		move.b	#$F0,$5555*2(a5,d0.l)	* ...programming fails
		bra.b	Programming_Error		* Go back to where Flash_Prog fails
* ---------------------------------------------------------------------------
Flash_29F_OK:
		subq.l	#1,d2
		bne.b	Flash_29F_Another		* OK so program another one
*		bra.w	Programming_OK

* ===========================================================================
* =============== End of Program AMD 29F010 FLASH chip types ================
* ===========================================================================


* ===========================================================================
*	d0 - used to return pass/fail
* ===========================================================================

Programming_OK:
		clr.w	d0
		bra.b	Programming_Return
* ---------------------------------------------------------------------------
Programming_Error:
		moveq	#1,d0
Programming_Return:
		rts

* ===========================================================================
* =============== End of Flash_Programming ==================================
* ===========================================================================


* =============== S U B	R O U T	I N E =======================================
* ===========================================================================
* =============== Erase_FLASH_Chips =========================================
* ===========================================================================
*
*
*	d0 - Used to return pass/fail (can also be used for anything temporarily)
*	d1 - used for delay loop counters
*	d2 - used to store/countdown the number of bytes to program to zero
*	d3 - used to store/countdown the number of bytes to program to zero
*	d4
*	d5 - used for programming retry counter
*	d6 - 0x5555 used for resetting the watchdog
*	d7 - 0xAAAA used for resetting the watchdog
*
*	a0
*	a1
*	a2
*	a3 - ;-)
*	a4
*	a5 - Flash_Start_Address either 0x40000 for T5.5 or 0x60000 for T5.2
*	a6 - Watchdog SWSR in SIM address
*
* ===========================================================================

* ===========================================================================
* =============== First work out what type of FLASH chips are fitted ========
* ===========================================================================
*
*	d0 - used for FLASH make
*		 and to return an error value if the FlASH isn't unrecognised
*	d1 - used for FLASH type
*
* ===========================================================================

Erase_FLASH_Chips:
		move.b	(FLASH_Make).w,d0
		move.b	(FLASH_Type).w,d1
		cmpi.b	#$89,d0					* Intel
		bne.b	Test_For_AMD
		cmpi.b	#$B8,d1					* Intel 28F512
		beq.b	Erase_28F512
		cmpi.b	#$B4,d1					* Intel 28F010
		beq.b	Erase_28F010
		moveq	#4,d0					* 4 means unrecognised Intel FLASH
		bra.w	Erase_Return
* ---------------------------------------------------------------------------
Test_For_AMD:
		cmpi.b	#1,d0					* AMD
		bne.b	Test_For_CSI
		cmpi.b	#$25,d1					* AMD 28F512
		beq.b	Erase_28F512
		cmpi.b	#$A7,d1					* AMD 28F010
		beq.b	Erase_28F010
		cmpi.b	#$20,d1					* check for AMD 29F010 Device id
		beq.w	Erase_AMD_29F			* CODE for erasing AMD 29F FLASH 
		moveq	#5,d0					* 5 means unrecognised AMD FLASH
		bra.w	Erase_Return
* ---------------------------------------------------------------------------
Test_For_CSI:
		cmpi.b	#$31,d0					* CSI/Catalyst
		bne.b	Test_For_Atmel
		cmpi.b	#$B4,d1					* CSI 28F010
		beq.b	Erase_28F010
		moveq	#6,d0					* 6 means unrecognised CSI FLASH
		bra.w	Erase_Return
* ---------------------------------------------------------------------------
Test_For_Atmel:
		cmpi.b	#$1F,d0					* Atmel
		bne.b	Unknown_FLASH
		cmpi.b	#$D5,d1					* Atmel 29C010 Device id
		beq.b	Erase_Atmel
		cmpi.b	#$5D,d1					* Atmel 29C512 Device id
		beq.b	Erase_Atmel
* ---------------------------------------------------------------------------
Unknown_FLASH:
		moveq	#3,d0					* 3 means unrecognised FLASH
		bra.w	Erase_Return

* ===========================================================================
* =============== Erase_Atmel ===============================================
* ===========================================================================
* 
* Atmel 29C010 FLASH chips don't need to be erased, simply return
*
* ===========================================================================

Erase_Atmel:
		moveq	#7,d0					* 7 means Atmel
		bra.w	Erase_Return			* Branch back to where Flash_Prog ends

* ===========================================================================
* =============== End of Erase_Atmel ========================================
* ===========================================================================

* ===========================================================================
* =============== Erase 28F512/010 FLASH chip types =========================
* ===========================================================================

Erase_28F010:
		move.l	#$40000,d2				* T5.5 FLASH size
		bra.b	Flash_Fill_With_Zero
Erase_28F512:
		move.l	#$20000,d2				* T5.2 FLASH size

* ===========================================================================
* =============== Fill 28F FLASH with zeroes ================================
* ===========================================================================
*
* Fills AMD/Intel/CSI 28F512/28F010 chips with 0x00 prior to erasing them
*
* FLASH is read before writing 0x00, and writing 0x00 is skipped if the
* FLASH already has that value.
*
* ===========================================================================
*
*	d0 - used to store a copy of the number of bytes to program to zero
*	d1 - used for delay loop counters, also used for dummy FLASH read
*	d2 - used to store/countdown the number of bytes to program to zero
*	d3 - used for 28F FLASH program command - 0x40
*	d4 - used for 28F FLASH verify command - 0xC0
*	d5 - used for programming retry counter
*	d6 - 0x5555 used for resetting the watchdog
*	d7 - 0xAAAA used for resetting the watchdog
*
*	a5 - Flash_Start_Address either 0x40000 for T5.5 or 0x60000 for T5.2
*	a6 - Watchdog SWSR in SIM address
*
* ===========================================================================

Flash_Fill_With_Zero:
		move.l	d2,d0				* Store a copy of FLASH size for erasing
		move.b	#$40,d3				* FLASH program command
		move.b	#$C0,d4				* FLASH verify command
		move.w	#$FFFF,(a5)			* Reset FLASH chips
		move.w	#$FFFF,(a5)			* by writing FF twice
* ---------------------------------------------------------------------------
Program_A_Zero:
		clr.w	(a5)				* Put_FLASH_In_Read_Mode
		tst.b	-1(a5,d2.l)			* Check if zero
		beq.b	Already_Zero
		moveq	#$19,d5				* 25 retries to	program
Flash_Zero_Loop:
		move.b	d3,-1(a5,d2.l)		* FLASH program command
		clr.b	-1(a5,d2.l)			* Write	0x00 data to flash address
		moveq 	#Count_10us,d1
Zero_Program_10us_Delay:
		nop
		dbeq	d1,Zero_Program_10us_Delay
		move.b	d4,-1(a5,d2.l)		* FLASH verify command
		moveq 	#Count_6us,d1
Zero_Verify_6us_Delay:
		nop
		dbeq	d1,Zero_Verify_6us_Delay
* Reset_Software_Watchdog
		move.w	d6,(a6)				* Write $5555 to SWSR in SIM
		move.w	d7,(a6)				* Write $AAAA to SWSR in SIM
		tst.b	-1(a5,d2.l)			* Check if zero
		bne.b	Zero_Not_Programmed
* ---------------------------------------------------------------------------
Already_Zero:
		subq.l	#1,d2				* decrease address counter for next byte
		bne.b	Program_A_Zero
		bra.b	Zeroing_Done
* ---------------------------------------------------------------------------
Zero_Not_Programmed:
		subq.w	#1,d5				* Reduce count of number of retries left
		bne.b	Flash_Zero_Loop		* Retry if some retries left		
* ---------------------------------------------------------------------------
Zeroing_Done:		
		clr.w	(a5)			* Put_FLASH_In_Read_Mode
		tst.w	(a5)			* Only needed for AMD, does no harm for Intel
		tst.b	d5				* Error if d5 = 0, - 25 attempts FAILED
		bne.b	Erase_28F_FLASH		* OK to erase if d5 < 25 attempts needed
		moveq	#2,d0			* 2 means writing zeroes failed
		bra.w	Erase_Return

* ===========================================================================
* =============== End of Fill 28F FLASH with zeroes =========================
* ===========================================================================


* ===========================================================================
* =============== Erase_28F_FLASH ===========================================
* ===========================================================================
*
*	d0 - used to store a copy of the number of bytes to program to zero
*		 also used to store 0xFF to check that bytes are erased
*	d1 - used for delay loop counters, also used for dummy FLASH read
*	d2 - used to store/countdown the number of bytes to program to zero
*	d3 - used for 28F FLASH erase command - 0x20
*	d4 - used for 28F FLASH verify command - 0xA0
*	d5 - used for programming retry counter
*	d6 - 0x5555 used for resetting the watchdog
*	d7 - 0xAAAA used for resetting the watchdog
*
*	a5 - Flash_Start_Address either 0x40000 for T5.5 or 0x60000 for T5.2
*	a6 - Watchdog SWSR in SIM address
*
* ===========================================================================

Erase_28F_FLASH:
		move.l	d0,d2			* Recall the copy of FLASH size for erasing
		move.b	#$FF,d0				* FLASH is 0xFF when erased
		move.b	#$20,d3				* FLASH erase command
		move.b	#$A0,d4				* FLASH erase verify command
		move.l	#$03E803E8,d5	* Maximum 1000 (0x3E8) Erase attempts
* ---------------------------------------------------------------------------
Erase_Flash:
		move.b	d3,-1(a5,d2.l)		* FLASH erase command
		move.b	d3,-1(a5,d2.l)		* FLASH erase command
		move.w	#Count_10ms,d1
Delay_Loop_While_Erase:
		nop
		dbeq	d1,Delay_Loop_While_Erase * Delay Loop
* ---------------------------------------------------------------------------
Verify_Erased:
		move.b	d4,-1(a5,d2.l)		* FLASH erase verify command
		moveq	#Count_6us,d1
Erase_Verify_6us_Delay:
		nop
		dbeq	d1,Erase_Verify_6us_Delay
* Reset_Software_Watchdog
		move.w	d6,(a6)				* Write $5555 to SWSR in SIM
		move.w	d7,(a6)				* Write $AAAA to SWSR in SIM
		cmp.b	-1(a5,d2.l),d0		* Verify FLASH Address is FF (Erased)
		bne.b	Byte_Not_Erased
* --------------- Byte is erased if here so move on to check next address ---
		swap	d5			* Can attempt to erase each FLASH chip 1000 times
		subq.l	#1,d2		* Point to the next address
*							* Have all locations been checked ? d2=0x2/40000
		bne.b	Verify_Erased		* Check next if not all done
		bra.b	Erasing_Done
* ---------------------------------------------------------------------------
Byte_Not_Erased:
		subq.w	#1,d5		* Reduce count of number of retries left
*							* Have maximum number of attempts been tried ?
		bne.b	Erase_Flash	* If not try again if d5 < then 1000 attempts
* ---------------------------------------------------------------------------
Erasing_Done:
		clr.w	(a5)		* Put_FLASH_In_Read_Mode
		tst.w	(a5)		* Only needed for AMD, does no harm for Intel
		tst.w	d5			* Erase was ok if < 1000
		beq.w	Erase_Failed	* All retry attempts were used up so fail
		bra.w	Erase_OK	* Erase_OK :-)

* ===========================================================================
* =============== End of Erase_28F_FLASH ====================================
* ===========================================================================


* ===========================================================================
* =============== Erase_AMD_29F =============================================
* ===========================================================================
*
* AMD 29F010 chips have an embedded erase algorithm
* Erase is checked by reading data to see if correct
* Bit DQ7 is inverted until erase algorithm is complete
* Bit DQ5 goes high if the erase process fails and a timeout error has occured
* Because DQ7 and DQ5 can change independently bit DQ7 needs to be checked
* again (with a second read of the FLASH chip) just in case a false timeout
* is indicated
*
*	d0 - used to select between FLASH chip1 and chip2
*	d1 - used for delay loop timer
*	d5 - used to check for a erasing ok or if there was a timeout error 
*	d6 - 0x5555 used for resetting the watchdog - also for AMD 29C commands
*	d7 - 0xAAAA used for resetting the watchdog - also for AMD 29C commands
*
*	a5 - used for Flash_Start_Address (already there)
*	a6 - Watchdog SWSR in SIM address
*
* ===========================================================================

Erase_AMD_29F:
		moveq	#1,d0
Erase_29F:
		move.b	d7,$5555*2(a5,d0.l)		*
		move.b	d6,$2AAA*2(a5,d0.l)		*
		move.b	#$80,$5555*2(a5,d0.l)	* 
		move.b	d7,$5555*2(a5,d0.l)		*
		move.b	d6,$2AAA*2(a5,d0.l)		*
		move.b	#$10,$5555*2(a5,d0.l)	* erase FLASH sequence
Erase_29F_Verify:
* Reset_Software_Watchdog
		move.w	d6,(a6)					* Write $5555 to SWSR in SIM
		move.w	d7,(a6)					* Write $AAAA to SWSR in SIM
		move.b	(a5,d0.l),d5			* read FLASH
		btst	#7,d5					* Bit 7 is 0 until erased then is 1
		bne.b	Erase_29F_OK
		btst	#5,d5					* Bit 5 is 1 if erase times out
		beq.b	Erase_29F_Verify
		move.b	(a5,d0.l),d5			* re-read FLASH !
		btst	#7,d5					* check for possible 'false' timeout
		bne.b	Erase_29F_OK
		move.b	d7,$5555*2(a5,d0.l)		* Erasing chip timed out if here
		move.b	d6,$2AAA*2(a5,d0.l)		* Have to reset FLASH chip when...
		move.b	#$F0,$5555*2(a5,d0.l)	* ...erasing fails
		bra.b	Erase_Failed			* Go back to Find_Flash... Fails
Erase_29F_OK:
		subq.l	#1,d0
		beq.w	Erase_29F				* Erase Chip OK so see if next chip
*		bra.w	Erase_OK				* Erase_OK :-)

* ===========================================================================
* =============== End of Erase_AMD_29F ====================================
* ===========================================================================


* ===========================================================================
*	d0 - used to return pass/fail
* ===========================================================================
	
Erase_OK:
* Erase AMD_29F returns here if ersaed OK
* ;-)
		movea.l	#FlashAddress,a3	* FLASH Buffer
		move.l	#$0007FE01,(a3)+
		move.l	#$0F4A7573,(a3)+
		move.l	#$7434704C,(a3)+
		move.l	#$65697375,(a3)+
		move.l	#$72653B29,(a3)
		jsr		(Flash_Programming).w
		clr.l	d0					* 0 means FLASH was erased
		bra.b	Erase_Return
Erase_Failed:
* Erase_AMD_29F returns here If Erase FAILED
		moveq	#1,d0				* 1 means FAILED to erase FLASH
Erase_Return:
		rts

* ===========================================================================
* =============== End of Erase_FLASH_Chips ==================================
* ===========================================================================


* =============== S U B	R O U T	I N E =======================================
* ===========================================================================
* =============== Get_Checksum ==============================================
* ===========================================================================
*
* First of all search backwards through the BIN file footer information to
* find the start and end addresses to calculate the checksum between.
*
* These are stored, backwards, as 'ascii' text representations and must be
* converted to an 0x 'long' value.
*
* ===========================================================================
*
*	d0 - used for 'footer' Identifier value
*	d1 - used for 'footer' Identifier 'string' length value
*	d2 - Start address for calculating the checksum
*	d3 - End address for calculating the checksum
*
*	a2 - used to find identifier strings in the 'footer'
*
* ===========================================================================

Get_Checksum:
		movea.l	#Last_Address_Of_T5-4,a2
		clr.l	d0
		clr.l	d1
		clr.l	d2				* ROM_Offset
		clr.l	d3				* Code_End
* ---------------------------------------------------------------------------
Search_For_ROM_Offset:
		move.b	(a2),d1			* String Length
		beq.w	Checksum_Error	* If zero then erasing failed
		cmpi.b	#$FF,d1
		beq.w	Checksum_Error	* If 0xFF then programming failed
		move.b	-1(a2),d0		* Identifier value
		suba.l	d1,a2			* Subtract string length and another 2 for
		subq.l	#2,a2			* length and identifier bytes to get to start
*								* of the string
		cmpi.b	#$FD,d0			* Check for ROM_Offset identifier
		bne.b	Search_For_ROM_Offset	* Keep looking
* ---------------------------------------------------------------------------
Read_ROM_Offset:
		move.b	(a2,d1.l),d0	* Get an ascii character from the ROM_Offset
		subi.b	#$30,d0			* Subtract ascii '0' (0x30)
		cmpi	#$A,d0			* see if the result is 0-9 (less than 10 (0xA)
		bcs.b	Get_ROM_Offset	
		subq.b	#7,d0			* Subtract 7 ('A'(0x41) - '0'(0x30) - 10)
*								* (because value is 10-15 - 0xA-0xF)
* ---------------------------------------------------------------------------
Get_ROM_Offset:
		lsl.l	#4,d2			* ROM_Offset, 'shift' to make room 
		or.b	d0,d2			* put in next hex value
		subq.b	#1,d1			* 1 less hex value to get
		bne.b	Read_ROM_Offset	* keep going if not all values read in yet
* ---------------------------------------------------------------------------
Search_Code_End:
		move.b	(a2),d1
		beq.w	Checksum_Error
		cmpi.b	#$FF,d1
		beq.w	Checksum_Error
		move.b	-1(a2),d0
		suba.l	d1,a2
		subq.l	#2,a2
		cmpi.b	#$FE,d0			* Check for Code_End identifier
		bne.b	Search_Code_End
* ---------------------------------------------------------------------------
Read_Code_End:
		move.b	(a2,d1.l),d0
		subi.b	#$30,d0
		cmpi	#$A,d0
		bcs.b	Get_Code_End
		subq.b	#7,d0
* ---------------------------------------------------------------------------
Get_Code_End:
		lsl.l	#4,d3			* Code_End
		or.b	d0,d3
		subq.b	#1,d1
		bne.b	Read_Code_End
* ---------------------------------------------------------------------------
* d2 now has the ROM_Offset
* d3 now has the Code_End

		cmp.l	d2,d3			* Check if Code_End is before ROM_Offset !!!
		bls.b	Checksum_Error
		cmpi.l	#Last_Address_Of_T5,d3	* Check if Code_End is past end of T5
		bcc.b	Checksum_Error
		addq.l	#1,d3

* ===========================================================================
* =============== Calculate_Checksum ========================================
* ===========================================================================
*
* Calculates a checksum of all the bytes between the ROM_Offset and Code_End
* addresses. The checksum just adds up all the byte values as a 'long' value.
*
* The watchdog must be reset after each byte is added because there is no way
* of easily calculating 'chunks' of the checksum before resetting the
* watchdog.
*
*	d0 - used to return the calculated checksum
*	d1 - used to fetch each byte when calculating
*	d2 - Value of dirst address to calculate from
*	d3 - value of last address to calculate to
*	d6 - 0x5555 used for resetting the watchdog
*	d7 - 0xAAAA used for resetting the watchdog
*
*	a2 - address used to get byte values to calculate with
*	a6 - Watchdog SWSR in SIM address
*
* The calculated checksum is returned in D0
*
* ===========================================================================

Calculate_Checksum:
		movea.l	d2,a2   			* Address for checksum calculation
		clr.l	d0
		clr.l	d1
* ---------------------------------------------------------------------------
Do_Calculation:
* Reset_Software_Watchdog
		move.w	d6,(a6)				* Write 0x5555 to SWSR in SIM
		move.w	d7,(a6)				* Write 0xAAAA to SWSR in SIM
		move.b	(a2)+,d1
		add.l	d1,d0	
		cmpa.l	d3,a2
		bne.b	Do_Calculation
* ===========================================================================
* =============== End of Calculate_Checksum =================================
* ===========================================================================

Calculation_Complete:
		cmp.l	(Last_Address_Of_T5-3),d0	* Checksum stored in BIN file
		bne.b	Checksum_Error
		clr.b	(a1)+				* 0 PASS, CanTxBuffer1
		move.l	d0,(a1)				* Checksum in CanTxBuffer2-5
		bra.b	Checksum_Return
* ---------------------------------------------------------------------------
Checksum_Error:
		move.b	#1,(a1)				* 1 FAIL, CanTxBuffer1
Checksum_Return:
		rts

* ===========================================================================
* =============== End of Get_Checksum =======================================
* ===========================================================================


* =============== S U B	R O U T	I N E =======================================
* ===========================================================================
* =============== Get_FLASH_Id_Bytes ========================================
* ===========================================================================
*
*	d1 - used for delay loop timer
*
*	a5 - used for Flash_Start_Address
*
* FLASH id is obtained by putting the chip in a special mode
* This is done differently for 28Fxxx and 29F/Cxxx types od FLASH chip
* I have assumed that if the check for 28Fxxx types doesn't work then I can
* detect this because 29F/Cxxx types will just return the 'normal'
* contents of the FLASH chip at these locations.
* Normally FF FF  F7 FC - because that's how all T5 BIN files start
* Could be FF FF  FF FF - if the FLASH has been erased
* Could be 00 00  00 00 - if the FLASH has had all zeroes written to it
*
* None of the above byte values are the same as any of the expected id bytes
* So just check for Manufacturer codes $89 (Intel) and $01 (AMD) after the
* original FLASH id program, and if neither are found then go on to try
* to detect 29F/Cxxx type FLASH chips.
*
* ===========================================================================

Get_FLASH_Id_Bytes:
* ===========================================================================
* 		Code for 28Fxxx FLASH chips here
* ===========================================================================
		movea.l	#FLASH_Make,a2
		ori.w	#$40,($FFFC14).l		* Turn FLASH power on
		move.w  #10000,d1
Wait_For_FLASH_Power:
		nop
		dbeq	d1,Wait_For_FLASH_Power
		move.b	#$FF,(a5)				*
		move.b	#$FF,(a5)				* Writing FF twice resets 28Fxxx
		move.b	#$90,(a5)
		move.b	(a5),(a2)+				* Manufacturer id
		move.b	2(a5),(a2)				* Device id
		move.b	#$FF,(a5)				*
		move.b	#$FF,(a5)				* Writing FF twice resets 28Fxxx
		cmpi.b	#$89,-(a2)				* Check for Intel Manufacturer id
		beq.b	FLASH_id_return
		cmpi.b	#1,(a2)					* Check for AMD Manufacturer id
		beq.b	FLASH_id_return
		cmpi.b	#$31,(a2)				* Check for CSI Manufacturer id
		beq.b	FLASH_id_return
		andi.w	#$FFBF,($FFFC14).l		* Turn FLASH power off (not needed)
* ===========================================================================
* 		Code for 29F/Cxxx FLASH starts here
* ===========================================================================
		move.b	d7,$5555*2(a5)			* d7 = 0xAA
		move.b	d6,$2AAA*2(a5)			* d6 = 0x55
		move.b	#$90,$5555*2(a5)		* get FLASH id
		jsr		(Wait_10ms).w			* 10ms delay for Atmel devices
		move.b	(a5),(a2)+				* Manufacturer id
		move.b	2(a5),(a2)				* Device id
		move.b	d7,$5555*2(a5)			* d7 = 0xAA
		move.b	d6,$2AAA*2(a5)			* d6 = 0x55
		move.b	#$F0,$5555*2(a5)		* Reset 29F/Cxxx FLASH chip
		jsr		(Wait_10ms).w			* 10ms delay for Atmel devices
FLASH_id_return:
		rts

* ===========================================================================
* =============== End of Get_FLASH_Id_Bytes =================================
* ===========================================================================


* =============== S U B	R O U T	I N E =======================================
* ===========================================================================
* =============== Wait_10ms =================================================
* ===========================================================================
*
* Atmel FLASH chips need a 10ms delay for some things
* NOTE also reset the watchdog to stop T5 ECU restarting !
*
* ===========================================================================
*
*	d1 - used for delay loop timer
*	d6 - 0x5555 used for resetting the watchdog
*	d7 - 0xAAAA used for resetting the watchdog
*
*	a6 - Watchdog SWSR in SIM address
*
* ===========================================================================

Wait_10ms:
		move.w	#Count_10ms,d1
Wait_10ms_loop:
		nop
		dbeq	d1,Wait_10ms_loop
* Reset_Software_Watchdog
		move.w	d6,(a6)				* Write $5555 to SWSR in SIM
		move.w	d7,(a6)				* Write $AAAA to SWSR in SIM
		rts

* ===========================================================================
* =============== End of Wait_10ms ==========================================
* ===========================================================================


* ===========================================================================
*
* 	Data area used for storing various things :-)
*
* ===========================================================================

CanRxBuffer:	ds.b	8				* 8 Bytes for CAN Receive messages
*
CanTxBuffer:	ds.b	8				* 8 Bytes for CAN Transmit messages
*
FLASH_Make:		dc.b	0
FLASH_Type:		dc.b	0
*
FlashAddress:	dc.l	0
FlashLength:	dc.b	0
FlashBuffer:	ds.b	128				* 128 Bytes for FLASH Buffer

* ===========================================================================

		END My_Booty
