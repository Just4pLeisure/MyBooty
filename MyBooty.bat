as32 -l -s MyBooty.asm >MyBooty.lst
srec2bin.exe -f 00 MyBooty.S19 temp.bin
bin2srec.exe -b 5000 -l 28 temp.bin >MyBooty.S19
del temp.bin
pause
