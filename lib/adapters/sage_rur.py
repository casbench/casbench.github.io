# Executed by sage_server.py with INPUT_POLYS and INPUT_VARS bound. Singular
# computes a lexicographic basis; its shape-position form yields an RUR.
# A system without a separating last variable is honestly reported unsolved.
t0 = walltime()
R = PolynomialRing(QQ, names=INPUT_VARS, order='lex')
P = PolynomialRing(QQ, 'T')
T = P.gen()
n = len(INPUT_VARS)
f = [R(s.replace('//', '/')) for s in INPUT_POLYS]
basis = R.ideal(f).groebner_basis('libsingular:std')

def project(g, index=None):
    a, b = P.zero(), P.zero()
    for exponent, coefficient in g.dict().items():
        if any(exponent[k] != 0 for k in range(n - 1) if k != index):
            return None
        if index is not None and exponent[index] > 1:
            return None
        term = P(coefficient) * T ** exponent[n - 1]
        if index is not None and exponent[index] == 1:
            a += term
        else:
            b += term
    return a, b

univariate = [project(g) for g in basis]
eliminators = [b for entry in univariate if entry is not None for a, b in [entry] if b.degree() > 0]
if not eliminators:
    raise ValueError('unsupported operation: no univariate elimination polynomial')
elim = min(eliminators, key=lambda p: p.degree()).monic()
relations = []
for i in range(n - 1):
    candidates = [r for g in basis for r in [project(g, i)] if r is not None and not r[0].is_zero()]
    if not candidates:
        raise ValueError('unsupported operation: no shape-position lifting map')
    relations.append(min(candidates, key=lambda r: r[0].degree() + r[1].degree()))
denom = P.one()
for a, b in relations:
    denom = lcm(denom, a)
params = [-b * (denom // a) for a, b in relations] + [T * denom]
roots = elim.roots(RealIntervalField(256), multiplicities=False)
solutions = []
for root in roots:
    t = QQ(root.center())
    d = denom(t)
    if d == 0:
        raise ValueError('unsupported operation: zero denominator at sampled root')
    solutions.append([p(t) / d for p in params])
t1 = walltime()
print('<<TIME>>', t1 - t0)
print('<<ELIM>>', ','.join(str(c) for c in elim.list()))
print('<<DEN>>', ','.join(str(c) for c in denom.list()))
for p in params:
    print('<<PAR>>', ','.join(str(c) for c in (p.list() or [0])))
for sol in solutions:
    print('<<SOL>>', ','.join(str(c) for c in sol))
