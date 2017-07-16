# makefile
# This makes "dblist"

dblist: dblist.ec
	c4gl -O dblist.ec -o dblist -s
	@rm -f dblist.c
