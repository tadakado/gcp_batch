# Copyright (c) 2019 Tadashi Kadowaki.
#
# a sample program

import sys
import numpy as np

args = sys.argv

name = args[1]
n = int(args[2])

m = np.random.normal(size=n**2).reshape(n,n)
mi = np.linalg.inv(m)

print(sum(np.diag(mi @ m)))

file = 'results/npz/' + name + '.npz'
np.savez(file, m, mi)

