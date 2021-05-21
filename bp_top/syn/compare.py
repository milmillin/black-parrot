import sys

# $fwrite(file_2, "instr,src,dst,mispred,taken,btb,ltb\n");
def parse(s):
    t = s.split(",")
    return (int(t[0]), t[1], t[2], int(t[3]), int(t[4]), int(t[5]), int(t[6]))


def readCSV(filename):
    file = open(filename, 'r')
    lines = file.readlines()
    file.close()
    return [parse(s) for s in lines[1:]]

def compare(ltb_trace, org_trace):
    assert(len(ltb_trace) == len(org_trace))
    ltb_mispred_cnt = 0
    org_mispred_cnt = 0
    ltb_better = 0
    ltb_worsen = 0
    for i, ltb_entry in enumerate(ltb_trace):
        _, _, _, mispred, _, _, ltb = ltb_entry
        _, _, _, org_mispred, _, _, _ = org_trace[i]

        ltb_mispred_cnt += mispred
        org_mispred_cnt += org_mispred
        if ltb:
            if (not mispred) and org_mispred:
                ltb_better += 1
            if mispred and (not org_mispred):
                ltb_worsen += 1
    return (ltb_mispred_cnt, org_mispred_cnt, ltb_better, ltb_worsen)
    
ltb_trace = readCSV(sys.argv[1])
org_trace = readCSV(sys.argv[2])

ltb_mispred_cnt, org_mispred_cnt, ltb_better, ltb_worsen = compare(ltb_trace, org_trace)

print("             Branch: %d" % (len(ltb_trace)))
print("     Old Mispredict: %d" % (org_mispred_cnt))
print("     New Mispredict: %d" % (ltb_mispred_cnt))
print("     Improve by LTB: %d" % (ltb_better))
print("      Worsen by LTB: %d" % (ltb_worsen))

