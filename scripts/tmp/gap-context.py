import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
lines=open(r'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log',encoding='utf-8',errors='replace').readlines()
for label,a,b in [('GAP208',1088,1110),('QUIT_DAD1',1688,1710),('GAP1431_end',2825,2850),('QUIT_DAD2',3175,3229)]:
    print(f'\n===== {label} L{a}-{b} =====')
    for i in range(a-1,min(b,len(lines))):
        print(f'{i+1}:{lines[i].rstrip()[:200]}')
