/* 
 * Copyright (C) 2016 severalnines.com
 */
#pragma once

#include "S9sString"

class S9sFormatter
{
    public:
        bool useSyntaxHighLight() const;

        const char *directoryColorBegin() const;
        const char *directoryColorEnd() const;
        
        S9sString bytesToHuman(ulonglong bytes) const;
        S9sString mBytesToHuman(ulonglong mBytes) const;
        S9sString kiloBytesToHuman(ulonglong kBytes) const;

        S9sString percent(const ulonglong total, const ulonglong part) const;

};
