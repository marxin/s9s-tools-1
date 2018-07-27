/* 
 * Copyright (C) 2016 severalnines.com
 */
#include "s9sformatter.h"

#include "S9sOptions"

//#define DEBUG
#define WARNING
#include "s9sdebug.h"

bool
S9sFormatter::useSyntaxHighLight() const
{
    S9sOptions *options = S9sOptions::instance();
   
    return options->useSyntaxHighlight();
}

const char *
S9sFormatter::directoryColorBegin() const
{
    if (useSyntaxHighLight())
        return XTERM_COLOR_DIR;

    return "";
}

const char *
S9sFormatter::directoryColorEnd() const
{
    if (useSyntaxHighLight())
        return TERM_NORMAL;

    return "";
}

S9sString 
S9sFormatter::bytesToHuman(
        ulonglong bytes) const
{
    S9sOptions *options = S9sOptions::instance();
    S9sString   retval;
    S9sVariant  variant = bytes;

    if (!options->humanReadable())
    {
        retval.sprintf("%'llu", variant.toULongLong());
    } else if (variant.toTBytes() > 1.0)
    {
        retval.sprintf("%.1fTB", variant.toTBytes());
    } else if (variant.toGBytes() >= 1.0) 
    {
        retval.sprintf("%.1fGB", variant.toGBytes());
    } else {
        retval.sprintf("%.1fMB", variant.toMBytes());
    }

    return retval;
}

S9sString 
S9sFormatter::mBytesToHuman(
        ulonglong mBytes) const
{
    return bytesToHuman(mBytes * (1024ull * 1024ull));
}

S9sString 
S9sFormatter::kiloBytesToHuman(
        ulonglong kBytes) const
{
    return bytesToHuman(kBytes * 1024ull);
}

S9sString
S9sFormatter::percent(
        const ulonglong total,
        const ulonglong part) const
{
    S9sString retval;
    double    percent = 100.0 * ((double)part / (double)total);

    retval.sprintf("%.1f%%", percent);
    return retval;
}
