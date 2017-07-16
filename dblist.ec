/*
    dblist.ec - dumps the contents of a database table to stdout
    Copyright (C) 1989-1992  David A. Snyder
 
    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; version 2 of the License.
 
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
 
    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
*/

#ifndef lint
static char sccsid[] = "@(#) dblist.ec 4.0  93/12/24 15:39:10";
#endif /* not lint */


#include <ctype.h>
#include <malloc.h>
#include <stdio.h>
#include "decimal.h"
$include sqlca;
$include sqlda;
$include sqltypes;
$include varchar;
$include datetime;
$include locator;

#define SUCCESS 0

char    *database = NULL, *index = NULL, *table = NULL, *value = NULL;
void	exit();

struct sqlda *tab_desc;
$struct _systables {
	char	tabname[19];
	char	owner[9];
	char	dirpath[65];
	long	tabid;
	short	rowsize;
	short	ncols;
	short	nindexes;
	long	nrows;
	long	created;
	long	version;
	char	tabtype[2];
	char	audpath[65];
} systables;

main(argc, argv)
int     argc;
char    *argv[];
{
        $char   exec_stmt[64], qry_stmt[256], sys_stmt[128];
        extern char     *optarg;
        extern int      optind, opterr;
        int     c, i, dflg = 0, errflg = 0, hflg = 0, iflg = 0, tflg = 0;

	/* Print copyright message */
	(void)fprintf(stderr, "DBLIST version 4.0, Copyright (C) 1989-1992 David A. Snyder\n\n");

        /* get command line options */
        while ((c = getopt(argc, argv, "d:hi:t:")) != EOF)
                switch (c) {
                case 'd':
                        dflg++;
                        database = optarg;
                        break;
                case 'h':
			if (iflg)
				errflg++;
			else
                        	hflg++;
                        break;
                case 'i':
			if (hflg)
				errflg++;
			else {
                        	iflg++;
                        	index = optarg;
			}
                        break;
                case 't':
                        tflg++;
                        table = optarg;
                        break;
                default:
                        errflg++;
                        break;
                }

	if (argc > optind)
		value = argv[argc - 1];

        /* validate command line options */
        if (errflg || !dflg || !tflg) {
		(void)fprintf(stderr, "usage: %s -d dbname -t tabname [-i idxname [value] | -h]\n", argv[0]);
                exit(1);
        }

        /* locate the database in the system */
        sprintf(exec_stmt, "database %s", database);
        $prepare db_exec from $exec_stmt;
        $execute db_exec;
        if (sqlca.sqlcode != SUCCESS) {
                (void)fprintf(stderr, "Database not found or no system permission.\n");
                exit(1);
        }

        /* build the select statement */
        sprintf(qry_stmt, "select * from %s", table);
	if (iflg)
		get_whereorder(qry_stmt);

        /* prepare the select statement */
        $prepare tab_query from $qry_stmt;
        if (sqlca.sqlcode != SUCCESS) {
                fprintf(stderr, "Table %s not found.\n", table);
                exit(1);
        }

	/* read and print header information */
        sprintf(exec_stmt, "update statistics for table %s", table);
        $prepare sys_exec from $exec_stmt;
        $execute sys_exec;
        sprintf(sys_stmt, "select nindexes, rowsize, nrows from systables where tabname = \"%s\"", table);
        $prepare sys_query from $sys_stmt;
        $declare sys_cursor cursor for sys_query;
	$open sys_cursor;
	$fetch sys_cursor into $systables.nindexes, $systables.rowsize, $systables.nrows;
	$close sys_cursor;
	(void)printf("Number of keys defined: %d\n", systables.nindexes);
	(void)printf("Data record size: %d\n", systables.rowsize);
	(void)printf("Number of records in file: %ld\n\n", systables.nrows);
	if (hflg)
		exit(0);

        /* build the description structure and allocate some memory */
        $describe tab_query into tab_desc;
        for (i = 0; i < tab_desc->sqld; i++) {
                if (tab_desc->sqlvar[i].sqltype == SQLCHAR ||
                    tab_desc->sqlvar[i].sqltype == SQLVCHAR)
                        tab_desc->sqlvar[i].sqllen++;
                if (tab_desc->sqlvar[i].sqltype == SQLTEXT ||
                    tab_desc->sqlvar[i].sqltype == SQLBYTES) {
                	tab_desc->sqlvar[i].sqldata = malloc(sizeof(loc_t));
                	_locate(tab_desc->sqlvar[i].sqldata, 12, 0,(char *)0);
		} else
                	tab_desc->sqlvar[i].sqldata = malloc(tab_desc->sqlvar[i].sqllen);
	}

        /* declare the cursor */
        $declare tab_cursor cursor for tab_query;

        /* read the database for the table and create some output */
        $open tab_cursor;
        $fetch tab_cursor using descriptor tab_desc;
        while (sqlca.sqlcode == SUCCESS) {
                output_row();
                $fetch tab_cursor using descriptor tab_desc;
        }
        $close tab_cursor;

	exit(0);
}


/*******************************************************************************
* This function will create the "where" and "order by" clauses for the select. *
*******************************************************************************/

get_whereorder(qry_stmt)
char	*qry_stmt;
{
	$char	colname[19], idx_stmt[256];
	$short	part1, part2, part3, part4, part5, part6, part7, part8;

        sprintf(idx_stmt, "%s %s %s%s%s",
	  "select part1, part2, part3, part4, part5, part6, part7, part8, colname",
	  "  from sysindexes, syscolumns",
	  "  where idxname = \"", index, "\" and sysindexes.tabid = syscolumns.tabid and colno = part1");
	$prepare idx_query from $idx_stmt;
	$declare idx_cursor cursor for idx_query;

	$open idx_cursor;
	$fetch idx_cursor into $part1, $part2, $part3, $part4, $part5, $part6, $part7, $part8, $colname;
	if (sqlca.sqlcode != SUCCESS) {
		fprintf(stderr, "Index %s not found.\n", index);
		exit(1);
	}
	$close idx_cursor;

	if (value != NULL)
		sprintf(qry_stmt, "%s where %s >= \"%s\"", qry_stmt, colname, value);

        sprintf(qry_stmt, "%s order by %d", qry_stmt, part1);
	if (part2 != 0)
        	sprintf(qry_stmt, "%s, %d", qry_stmt, part2);
	if (part3 != 0)
        	sprintf(qry_stmt, "%s, %d", qry_stmt, part3);
	if (part4 != 0)
        	sprintf(qry_stmt, "%s, %d", qry_stmt, part4);
	if (part5 != 0)
        	sprintf(qry_stmt, "%s, %d", qry_stmt, part5);
	if (part6 != 0)
        	sprintf(qry_stmt, "%s, %d", qry_stmt, part6);
	if (part7 != 0)
        	sprintf(qry_stmt, "%s, %d", qry_stmt, part7);
	if (part8 != 0)
        	sprintf(qry_stmt, "%s, %d", qry_stmt, part8);
}


/*******************************************************************************
* This function prints an entire row of data.                                  *
*******************************************************************************/

output_row()
{
        char    buffer[33];
        int     i;

        for (i = 0; i < tab_desc->sqld; i++) {
                switch (tab_desc->sqlvar[i].sqltype) {
                case SQLCHAR:
                case SQLVCHAR:
                        if (!risnull(SQLCHAR, tab_desc->sqlvar[i].sqldata)) {
                                rtrim(tab_desc->sqlvar[i].sqldata);
                                printf("%s", tab_desc->sqlvar[i].sqldata);
                        }
                        break;
                case SQLSMINT:
                        if (!risnull(SQLSMINT, tab_desc->sqlvar[i].sqldata))
                                printf("%d", *((short *)(tab_desc->sqlvar[i].sqldata)));
                        break;
                case SQLINT:
                case SQLSERIAL:
                        if (!risnull(SQLINT, tab_desc->sqlvar[i].sqldata))
                                printf("%ld", *((long *)(tab_desc->sqlvar[i].sqldata)));
                        break;
                case SQLFLOAT:
                        if (!risnull(SQLFLOAT, tab_desc->sqlvar[i].sqldata))
                                printf("%f", *((double *)(tab_desc->sqlvar[i].sqldata)));
                        break;
                case SQLSMFLOAT:
                        if (!risnull(SQLSMFLOAT, tab_desc->sqlvar[i].sqldata))
                                printf("%f", *((float *)(tab_desc->sqlvar[i].sqldata)));
                        break;
                case SQLMONEY:
                        putchar('$');
                case SQLDECIMAL:
                        if (!risnull(SQLDECIMAL, tab_desc->sqlvar[i].sqldata)) {
                                dectoasc(tab_desc->sqlvar[i].sqldata, buffer, sizeof(buffer), -1);
				buffer[32] = '\0';
                                rtrim(buffer);
                                printf("%s", buffer);
                        }
                        break;
                case SQLDATE:
                        if (!risnull(SQLDATE, tab_desc->sqlvar[i].sqldata)) {
                                rdatestr(*((long *)(tab_desc->sqlvar[i].sqldata)), buffer);
                                printf("%s", buffer);
                        }
                        break;
                case SQLBYTES:
                        if (!risnull(SQLBYTES, tab_desc->sqlvar[i].sqldata))
                                printf("<BYTE value>");
                        break;
                case SQLTEXT:
                        if (!risnull(SQLTEXT, tab_desc->sqlvar[i].sqldata))
                                printf("<TEXT value>");
                        break;
                case SQLDTIME:
                        if (!risnull(SQLDTIME, tab_desc->sqlvar[i].sqldata)) {
                                dttoasc(tab_desc->sqlvar[i].sqldata, buffer);
                                rtrim(buffer);
                                printf("%s", buffer);
                        }
                        break;
                case SQLINTERVAL:
                        if (!risnull(SQLINTERVAL, tab_desc->sqlvar[i].sqldata)) {
                                intoasc(tab_desc->sqlvar[i].sqldata, buffer);
                                rtrim(buffer);
                                printf("%s", buffer);
                        }
                        break;
                }

                if (i != tab_desc->sqld - 1)
                        putchar(',');
        }

        putchar('\n');
}


/*******************************************************************************
* This function will trim trailing spaces from s.                              *
*******************************************************************************/

rtrim(s)
char    *s;
{
        int     i;

        for (i = strlen(s) - 1; i >= 0; i--)
                if (!isgraph(s[i]) || !isascii(s[i]))
                        s[i] = '\0';
                else
                        break;
}


