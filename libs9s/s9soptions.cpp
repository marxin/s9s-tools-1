/*
 * Severalnines Tools
 * Copyright (C) 2016  Severalnines AB
 *
 * This file is part of s9s-tools.
 *
 * s9s-tools is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * Foobar is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Foobar. If not, see <http://www.gnu.org/licenses/>.
 */
#include "s9soptions.h"

#include "S9sFile"

#include <cstdlib>
#include <getopt.h>

#define DEBUG
#define WARNING
#include "s9sdebug.h"

S9sOptions *S9sOptions::sm_instance = 0;

S9sOptions::S9sOptions() :
    m_operationMode(NoMode),
    m_exitStatus(EXIT_SUCCESS)
{
    sm_instance = this;
}

S9sOptions::~S9sOptions()
{
    sm_instance = NULL;
}

S9sOptions *
S9sOptions::instance()
{
    if (!sm_instance)
        sm_instance = new S9sOptions;

    return sm_instance;
}

void 
S9sOptions::uninit()
{
    if (sm_instance)
    {
        delete sm_instance;
        sm_instance = 0;
    }
}


S9sString
S9sOptions::binaryName() const
{
    return m_myName;
}

int 
S9sOptions::exitStatus() const 
{ 
    return m_exitStatus; 
}

S9sString 
S9sOptions::errorString() const
{
    return m_errorMessage;
}


bool
S9sOptions::readOptions(
        int   *argc,
        char  *argv[])
{
    bool retval = true;

    S9S_DEBUG("*** argc: %d", *argc);
    if (*argc < 1)
    {
        m_errorMessage = "Missing command line options.";
        return false;
    }

    m_myName = S9sFile::basename(argv[0]);
    if (*argc < 2)
    {
        m_errorMessage = "Missing command line options.";
        return false;
    }

    retval   = setMode(argv[1]);
    if (!retval)
        return retval;

    switch (m_operationMode)
    {
        case NoMode:
        case Cluster:
            S9S_DEBUG("Unhandled mode.");
            break;

        case Node:
            retval = readOptionsNode(*argc, argv);
            break;
    }

    return retval;
}

bool 
S9sOptions::setMode(
        const S9sString &modeName)
{
    bool retval = true;
    
    if (modeName == "cluster") 
    {
        m_operationMode = Cluster;
    } else if (modeName == "node")
    {
        m_operationMode = Node;
    } else {
        m_errorMessage = "The first command line option must be the mode.";
        retval = false;
    }

    return retval;
}

bool
S9sOptions::readOptionsNode(
        int    argc,
        char  *argv[])
{
    int           c;
    struct option long_options[] =
    {
        { "help",          no_argument,       0, 'h' },
        { "verbose",       no_argument,       0, 'v' },
        { 0, 0, 0, 0 }
    };

    for (;;)
    {
        int option_index = 0;
        c = getopt_long(argc, argv, "hv", long_options, &option_index);

        if (c == -1)
            break;

        switch (c)
        {
            case 'h':
                //print_help_and_exit(EXIT_SUCCESS);
                break;

            case 'v':
                //g_option_verbose = 1;
                break;

            default:
                #if 0
                m_errorMessage.sprintf(
                        "Invalid command line option option '%s'.",
                        argv[option_index]);
                #endif
                return false;
        }
    }

    return true;
}
