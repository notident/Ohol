#!/usr/bin/env python3
"""Writes the list of .cpp files for the single-binary browser build
(client + server + in-memory network) to stdout, one absolute path per line.

usage: gen_sources.py <workdir containing OneLife/ and minorGems/>
"""
import os, re, subprocess, sys

work = os.path.abspath(sys.argv[1])
repo = os.path.join(work, 'OneLife')
mg = os.path.join(work, 'minorGems')


def make_list(dirname, filename):
    """LAYER_SOURCE entries of a makeFileList, as absolute paths"""
    base = os.path.join(repo, dirname)
    text = open(os.path.join(base, filename)).read()
    block = text.split('LAYER_SOURCE')[1].split('GAME_GRAPHICS')[0] \
        if 'GAME_GRAPHICS' in text else text.split('LAYER_SOURCE')[1].split('NEEDED_MINOR_GEMS_OBJECTS')[0]
    out = []
    for tok in re.findall(r'[\w./+-]+\.cpp', block):
        out.append(os.path.normpath(os.path.join(base, tok)))
    return out


def minorgems_list(dirname):
    """the minorGems .cpp files a platform makefile links in, taken from the
    dependency command the generated Makefile runs"""
    base = os.path.join(repo, dirname)
    subprocess.run('echo 1 | ./configure', shell=True, cwd=repo if dirname == 'gameSource' else base,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out = subprocess.run(['make', '-n', '-B'], cwd=base, capture_output=True, text=True).stdout
    for line in out.split('\n'):
        if ' -MM ' in line and 'minorGems/' in line and 'Makefile.minorGems_dependencies' in line:
            toks = re.findall(r'\S+minorGems/\S+\.cpp', line)
            return [os.path.normpath(os.path.join(base, t)) for t in toks]
    raise SystemExit('could not find minorGems list for ' + dirname)


client_app = make_list('gameSource', 'makeFileList')
server_app = make_list('server', 'makeFileList')
client_mg = minorgems_list('gameSource')
server_mg = minorgems_list('server')

# the real network layer is replaced by the in-memory one
drop = re.compile(r'network/linux/(Socket|HostAddress|SocketClient|SocketServer|SocketPoll)Linux\.cpp$')
emu = [os.path.join(mg, 'network/emscripten', f) for f in (
    'loopback.cpp', 'SocketEmscripten.cpp', 'SocketClientEmscripten.cpp',
    'SocketServerEmscripten.cpp', 'SocketPollEmscripten.cpp',
    'HostAddressEmscripten.cpp')]

seen = set()
result = []
for path in client_app + server_app + client_mg + server_mg + emu + \
        [os.path.join(repo, 'gameSource/embeddedServer.cpp')]:
    if drop.search(path):
        continue
    if path in seen:
        continue
    seen.add(path)
    result.append(path)

print('\n'.join(result))
