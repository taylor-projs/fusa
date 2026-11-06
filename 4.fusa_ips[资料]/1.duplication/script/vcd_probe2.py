import re, sys

data = open(sys.argv[1] if len(sys.argv) > 1 else 'dcls.vcd').read()
head, body = data.split('$enddefinitions')

# build id -> full path name (track $scope)
scope = []
id2name = {}
for line in head.splitlines():
    if line.startswith('$scope'):
        scope.append(line.split()[2])
    elif line.startswith('$upscope'):
        if scope: scope.pop()
    elif line.startswith('$var'):
        m = re.match(r'\$var\s+\w+\s+\d+\s+(\S+)\s+(\S+)', line)
        if m:
            id2name.setdefault(m.group(1), '.'.join(scope + [m.group(2)]))

pat = re.compile(sys.argv[2] if len(sys.argv) > 2 else r'en_dcls|mclk_dcls|reset_n|fault_injection|err_fusadcls')
t = 0
for line in body.splitlines():
    if line.startswith('#'):
        t = line[1:]
    elif line[:1] in '01xzXZ' and len(line) > 1:
        name = id2name.get(line[1:], line[1:])
        if pat.search(name):
            print(t, name, '=', line[0])
    elif line.startswith('b'):
        parts = line.split()
        if len(parts) >= 2:
            name = id2name.get(parts[1], parts[1])
            if pat.search(name):
                print(t, name, '=', parts[0][1:])
