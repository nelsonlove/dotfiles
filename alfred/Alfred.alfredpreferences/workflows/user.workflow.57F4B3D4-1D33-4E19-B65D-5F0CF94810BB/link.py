try:
    from urllib.request import urlopen
except ImportError:
    from urllib2 import urlopen
import os
import sys
url = sys.argv[1].rstrip()
f = urlopen(url)
resp = str(f.read())
f.close()
title = resp.split('<title>')[1].split('</title>')[0]
link = '[%s](%s)' % (title, url)
print(link.strip())