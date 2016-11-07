.section  .init
.globl    _start

_start:
    b   main

.section .text

main:
    mov sp, #0x8000                             //initializes stack pointer
    bl  EnableJTAG                              // enables JTAG
    bl  InitUART                                //initializes UART

    ldr r0, =CreatorMsg                         //prompts user with CreatorMsg
    bl  Print_Message


//##### can move common codes down into Init_GPIO
    ldr r0, =0x3F200000                         //loads base reg address into r0
    mov r1, #1                                  //loads function code for output into r1
    mov r2, #9                                  //loads the pin# for latch into r2
    bl  Init_GPIO

    ldr r0, =0x3F200000                         //loads base reg address into r0
    mov r1, #0                                  //loads function code for output into r1
    mov r2, #10                                 //loads the pin# for data into r2
    bl  Init_GPIO

    ldr r0, =0x3F200000                         //loads base reg address into r0
    mov r1, #1                                  //loads function code for output into r1
    mov r2, #11                                 //loads the pin# for clock into r2
    bl  Init_GPIO


Main_Loop:
    ldr r0, =Prompt                             //loads prompt message address
    bl  Print_Message                           //prints prompt message

    bl  Read_SNES                               //branches to Read_SNES

    mov   r2, #0                                //clears register r2 as a counter
    mov   r3, #1                                //creates a single bit mask to check value for each button
    ldr   r0, =Response                         //loads response message address
    bl    Print_Message                         //prints response string

    checkLoop:
        tst   r4, r3                            //checks if button is pressed
        beq   update                            //if equal, then that particular button is not pressed

        ldr   r1, =Buttons                      //loads Buttons array address into r1
        ldr   r0, [r1, r2, lsl #2]              //loads corresponding string into r0
        bl    Print_Message                     //prints string

        ldr   r0, =Tab                          //prints a tab
        bl    Print_Message

        cmp   r2, #3                            //checks if it is the 4th button (START) pressed
        beq   haltLoop                          //terminates program

        update:
            add   r2, #1                        //increments counter by 1
            lsl   r3, #1                        //left shifts the mask by 1 bit to check the next bit
            cmp   r2, #11                       //we only care about the first 12 bits for now
            blt   checkLoop

        ldr   r0, =NewLine                      //prints new line
        bl    Print_Message

        bl    main                              //branches back to main
    //######Check loop, needs to have a counter
                            //r0 (which after Read_SNES has the 'buttonarray' ('B' in bit 0, etc)
                                                //need a single bit mask (tst) that we shift left by 1, to read each bit, and then compare that
                                                //to a 1, if nqe, reloop (bne), if eq, ldr from Buttons = counter*4
                                                //then branch to Print_Message, w/ Response, followed by Print_Message with address gotten from Buttons
                                                //extra check if start is read to bl to haltLoop$ after print


Init_GPIO:
    Loop:
        cmp   r2, #9                            //loops up to 9 times to check all 9 bits
        subhi r2, #10                           //if greater than 9, sub 10 from r2; r2 is pin# mod 10
        addhi r0, #4                            //if greater than 9, add 4 to r0; r0 is offset
        bhi   Loop                              //if greater than 9, branch back to loop

        add   r2, r2, lsl #1                    //add r2 to r2*2, ie r2*3; r2 is the 1st bit for pin#
        lsl   r1, r2                            //left shift function code by r2 amount

        mov   r3, #7
        lsl   r3, r2                            //left shift r3 by r2 amount

        ldr   r2, [r0]                          //load offset in r0 to r2
        bic   r2, r3                            //clears pin# bits
        orr   r2, r1                            //sets pin# function
        str   r2, [r0]                          //stores the value in r2 in r0 address
        bx    lr


Print_Message:
    push  {lr}
    movr  r1, #0                                //sets loop counter to 0
    mov   r2, r0                                //moves message address to r2

    printLoop:
        ldrb  r3, [r2], #1                      //loads byte to memory
        cmp   r3, #0                            //compares the byte to 0 (ASCII for null character)
        addne r1, #1                            //increments counter if not null character
        bne   printLoop                         //loops if no null character
                                                //counter = string length for WriteStringUART
        bl    WriteStringUART
        pop   {pc}                              //returns to calling code


Read_SNES:
            push  {r4,r5,lr}                    //pushes registers to retain values
            mov   r4, #0                        //clears r4, for button register
            mov   r0, #1                        //moves 1 into r0 as a parameter for writeclock
            bl    Write_Clock
            mov   r0, #1                        //sets latch to 1
            bl    Write_Latch
            mov   r0, #12                       //sets arguement for wait, waiting 12 microseconds
            bl    Wait
            mov   r0, #0                        //sets latch to 0
            bl    Write_Latch
            mov   r5, #0                        //counter register
            pulseLoop:
                        mov r0, #6              //requires to wait for 6 microseconds
                        bl  Wait
                        mov r0, #0              //sets clock to 0
                        bl  Write_Clock
                        mov r0, #6              //requires to wait for 6 microseconds
                        bl  Wait
                        bl  Read_Data
                        lsl r0, r5              //left shifting by counter
                        orr r4, r0              //setting bit in button register
                        add r5, #1              //increments counter
                        cmp r5, #16             //compares to 16
                        blt pulseLoop           //reloops if less than 16
                        mov r0, r4              //otherwise save value register into r0 (return value)
                        pop {r4, r5, pc}        //restore register values and return


Write_Latch:
        mov   r1, #9                            //pin#9 = Latch line
        ldr   r2, =0x3F200000                   //Base GPIO Register
        mov   r3, #1
        lsl   r3, r1
        teq   r0, #0
        streq r3, [r2, #40]                     //GPCLR0
        strne r3, [r2, #28]                     //GPSET0
        bx    lr


Write_Clock:
        mov   r1, #11                           //pin#11 = Clock line
        ldr   r2, =0x3F200000                   //Base GPIO Register
        mov   r3, #1
        lsl   r3, r1
        teq   r0, #0
        streq r3, [r2, #40]                     //GPCLR0
        strne r3, [r2, #28]                     //GPSET0
        bx    lr


//Returns in r0 the bit read.
Read_Data:
        mov   r0, #10                           //pin#10 = DATA Line
        ldr   r2, =0x3F200000                   //Base GPIO Register
        ldr   r1, [r2, #52]                     //GPLEV0
        mov   r3, #1
        lsl   r3, r0                            //aligns pin10 bit
        and   r1, r3                            //masks everything else
        teq   r1, #0
        moveq r0, #0                            //returns 0
        movne r0, #1                            //returns 1
        bx    lr


Wait:
     ldr r1, =#0x3F003004                       //address for low timer counter
     ldr r2, [r1]                               //loads clock value at r1 into r2
     add r0, r2                                 //adds the passed parameter in r0 to r2

     Wait_Loop:
                ldr r2, [r1]                    //loads value at address in r1 into r2
                cmp r0, r2                      //compares the two values
                bhi Wait_Loop                   //loops if r0(paramaterized time) is greater than our current time amount in r2
                bx  lr                          //returns

haltLoop$:
    b haltLoop$


CreatorMsg:
    .asciz "Created by: Keith Hamel, Daniel Van Leusen & Jared Madden\n\r" //author message

Prompt:
    .asciz "Please press a button...\n\r"                                 //prompt string

Response:
    .asciz "You have pressed "                                            //initial part of response string

Tab:
    .asciz "    "                                                         //tab of four spaces

NewLine:
    .asciz "\n\r"                                                         //new line

Buttons:
    .word B_Button, Y_Button, Select_Button, Start_Button, Up_Button, Down_Button, Left_Button, Right_Button, A_Button, X_Button, L_Button, R_Button

B_Button:
    .asciz "B"
Y_Button:
    .asciz "Y"
Select_Button:
    .asciz "Select"
Start_Button:
    .asciz "\n\rProgram is terminating...\n\r"
Up_Button:
    .asciz "Joy-Pad UP"
Down_Button:
    .asciz "Joy-Pad DOWN"
Left_Button:
    .asciz "Joy-Pad LEFT"
Rght_Button:
    .asciz "Joy-Pad RIGHT"
A_Button:
    .asciz "A"
X_Button:
    .asciz "X"
L_Button:
    .asciz "L"
R_Button:
    .asciz "R"

.section .data
