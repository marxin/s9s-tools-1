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
 * S9sTools is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with S9sTools. If not, see <http://www.gnu.org/licenses/>.
 */
#include "s9stopui.h"

#include "S9sRpcClient"
#include "S9sOptions"
#include "S9sDateTime"
#include "S9sMutexLocker"

#include <stdio.h>
#include <unistd.h>
#include <string.h>

#define DEBUG
#define WARNING
#include "s9sdebug.h"
        
struct termios orig_termios;

S9sTopUi::S9sTopUi(
        S9sRpcClient &client) :
    S9sDisplay(true),
    m_client(client),
    m_nReplies(0)
{
}

S9sTopUi::~S9sTopUi()
{
}

void
S9sTopUi::processKey(
        int key)
{
    switch (key)
    {
        case 'q':
        case 'Q':
        case 0x1b:
        case 3:
            exit(0);
            break;
    }
}

bool
S9sTopUi::refreshScreen()
{
    startScreen();
    printHeader();
    if (m_nReplies == 0)
        printMiddle("*** Waiting for data. ***");
    else
        printProcesses();
    
    printFooter();
    return true;
}

void
S9sTopUi::printHeader()
{
    S9sDateTime dt = S9sDateTime::currentDateTime();
    S9sString   title;

    title = "S9S TOP ";

    ::printf("%s%s%s ", TERM_SCREEN_TITLE_BOLD, STR(title), TERM_SCREEN_TITLE);
    ::printf("%c ", rotatingCharacter());
    ::printf("%s ", STR(dt.toString(S9sDateTime::LongTimeFormat)));

    if (m_nReplies > 0)
    {
        ::printf("%s - ", STR(m_clusterName));
        ::printf("%s ", STR(m_clustersReply.clusterStatusText(m_clusterId)));
        printNewLine();

        m_cpuStatsReply.printCpuStatLine1();
        printNewLine();

        m_memoryStatsReply.printMemoryStatLine1();
        printNewLine();

        m_memoryStatsReply.printMemoryStatLine2();
        printNewLine();
        
        printProcessList(rows() - 6);
    } else {
        printNewLine();
    }
}

static bool 
compareProcess(
        const S9sVariant &a,
        const S9sVariant &b)
{
    S9sVariantMap aMap = a.toVariantMap();
    S9sVariantMap bMap = b.toVariantMap();

    return aMap["cpu_usage"].toDouble() > bMap["cpu_usage"].toDouble();
}

void
S9sTopUi::printProcessList(
        int maxLines)
{
    S9sVariantList  hostList = m_processReply["data"].toVariantList();
    S9sVariantList  processList;

    S9sFormat       pidFormat;
    S9sFormat       userFormat(userColorBegin(), userColorEnd());
    S9sFormat       hostFormat(XTERM_COLOR_GREEN, TERM_NORMAL);
    S9sFormat       priorityFormat;
    S9sFormat       virtFormat;
    S9sFormat       resFormat;
    S9sFormat       stateFormat;
    S9sFormat       cpuFormat;
    S9sFormat       memFormat;
    S9sFormat       commandFormat("\033[1;2m\033[38;5;46m", TERM_NORMAL);
    
    for (uint idx = 0u; idx < hostList.size(); ++idx)
    {
        S9sString hostName = hostList[idx]["hostname"].toString();
        S9sVariantList processes = hostList[idx]["processes"].toVariantList();
    
        for (uint idx1 = 0u; idx1 < processes.size(); ++idx1)
        {
            S9sVariantMap processMap = processes[idx1].toVariantMap();

            processMap["hostname"] = hostName;
            processList << processMap;
        }
    }
    
    sort(processList.begin(), processList.end(), compareProcess);
    
    for (uint idx = 0u; idx < processList.size(); ++idx)
    {
        S9sProcess    process    = processList[idx].toVariantMap();
        int           pid        = process.pid();
        S9sString     user       = process.userName();
        S9sString     hostName   = process.hostName();
        int           priority   = process.priority();
        S9sString     rss        = process.resMem("");
        S9sString     virtMem    = process.virtMem("");

        if (maxLines > 0 && (int) idx >= maxLines)
            break;

        pidFormat.widen(pid);
        userFormat.widen(user);
        hostFormat.widen(hostName);
        priorityFormat.widen(priority);
        virtFormat.widen(virtMem);
        resFormat.widen(rss);
    }

    // Flickering of the widths is a bit annyoying, so we introduce some minimal
    // widths.
    userFormat.widen("xxxxxxxxxx");
    
    virtFormat.setRightJustify();
    resFormat.setRightJustify();
    
    if (!processList.empty())
    {
        pidFormat.widen("PID");
        userFormat.widen("USER");
        hostFormat.widen("HOST");
        priorityFormat.widen("PR");
        virtFormat.widen("VIRT");
        resFormat.widen("RES");
        stateFormat.widen("S");
        cpuFormat.widen("%CPU");
        memFormat.widen("%MEM");
        commandFormat.widen("COMMAND");

        printf("%s", TERM_SCREEN_HEADER);
        pidFormat.printf("PID", false);
        userFormat.printf("USER", false);
        hostFormat.printf("HOST", false);
        priorityFormat.printf("PR", false);
        virtFormat.printf("VIRT", false);
        resFormat.printf("RES", false);
        stateFormat.printf("S", false);
        cpuFormat.printf("%CPU", false);
        memFormat.printf("%MEM", false);
        commandFormat.printf("COMMAND", false);
        printNewLine();
    }
    

    for (uint idx = 0u; idx < processList.size(); ++idx)
    {
        S9sVariantMap processMap    = processList[idx].toVariantMap();
        S9sProcess    process    = processList[idx].toVariantMap();
        int           pid        = process.pid();
        S9sString     user       = process.userName();
        S9sString     hostName   = process.hostName();
        int           priority   = process.priority();

        double        cpuUsage   = processMap["cpu_usage"].toDouble();
        double        memUsage   = processMap["mem_usage"].toDouble();
        S9sString     state      = processMap["state"].toString();

        S9sString     rss        = process.resMem("");
        S9sString     virtMem    = process.virtMem("");
        S9sString     executable = processMap["executable"].toString();
        
        pidFormat.printf(pid);
        userFormat.printf(user);
        hostFormat.printf(hostName);
        priorityFormat.printf(priority);

        virtFormat.printf(virtMem);
        resFormat.printf(rss);

        printf("%1s ", STR(state));
        printf("%6.2f ", cpuUsage);
        printf("%6.2f ", memUsage); 
        commandFormat.printf(executable);

        printNewLine();
        if (maxLines > 0 && (int) idx + 1 >= maxLines)
            break;
    }
}

void
S9sTopUi::printFooter()
{
    const char *bold   = TERM_SCREEN_TITLE_BOLD;
    const char *normal = TERM_SCREEN_TITLE;

    // Goint to the last line.
    for (;m_lineCounter < rows() - 1; ++m_lineCounter)
    {
        ::printf("\n\r");
        ::printf("%s", TERM_ERASE_EOL);
    } 

    ::printf("%s ", normal);
    ::printf("%sQ%s-Quit", bold, normal);

    // No new-line at the end, this is the last line.
    ::printf("%s", TERM_ERASE_EOL);
    ::printf("%s", TERM_NORMAL);
    fflush(stdout);
}

void
S9sTopUi::printProcesses()
{
}

void
S9sTopUi::executeTop()
{
    S9sOptions  *options = S9sOptions::instance();
    int          clusterId = options->clusterId();
    bool         success;

    if (clusterId <= 0)
    {
        PRINT_ERROR("The cluster ID is invalid while executing 'top'.");
        exit (1);
    }

    for (;;)
    {
        success = executeTopOnce();

        if (!success)
            break;
        
        sleep(options->updateFreq());
    }
}

bool
S9sTopUi::executeTopOnce()
{
    S9sMutexLocker    locker(m_mutex);
    S9sOptions  *options     = S9sOptions::instance();
    int          clusterId   = options->clusterId();
    S9sString    clusterName = options->clusterName();
    S9sString    clusterStatusText;
    S9sRpcReply  reply;
    bool         success = true;
    S9sDateTime  date = S9sDateTime::currentDateTime();
    S9sString    dateString = date.toString(S9sDateTime::LongTimeFormat);
    int          terminalWidth = options->terminalWidth();
    int          columns;
    S9sString    tmp;

    //
    // The cluster information.
    //
    m_clusterId   = options->clusterId();
    m_clusterName = options->clusterName();

    success = m_client.getCluster(m_clusterName, m_clusterId);
    m_clustersReply = m_client.reply();
    if (!success)
        return success;

    m_client.getCpuStats(m_clusterId);
    m_cpuStatsReply = m_client.reply();
    
    m_client.getMemoryStats(m_clusterId);
    m_memoryStatsReply = m_client.reply();
    
    m_client.getRunningProcesses();
    m_processReply = m_client.reply();

    m_nReplies++;
    m_refreshCounter++;
    m_clusterName = m_clustersReply.clusterName(m_clusterId);
    return true;

    clusterStatusText = reply.clusterStatusText(clusterId);
        
    columns  = terminalWidth;
    columns -= clusterName.length();
    columns -= clusterStatusText.length();
    columns -= 13;
        
    tmp = S9sString::space * columns;

    printf("\033[0;0H");
    //printf("columns: %d\n", columns);
    printf("%s - %s ", STR(clusterName), STR(dateString));
    printf("%s", STR(tmp));
    printf("%s", STR(clusterStatusText));
    printf("\n");

    //
    // Summary of CPU usage.
    //
    m_client.getCpuStats(clusterId);
    reply = m_client.reply();

    reply.printCpuStatLine1();
   
    //
    // The memory summary.
    //
    m_client.getMemoryStats(clusterId);
    reply = m_client.reply();
    reply.printMemoryStatLine1();
    reply.printMemoryStatLine2();
    printf("\n");

    //
    // List of processes.
    //
    m_client.getRunningProcesses();
    reply = m_client.reply();

    reply.printProcessListTop(options->terminalHeight() - 7);


    if (!success)
    {
        PRINT_ERROR("%s", STR(m_client.errorString()));
    }

    return success;
}

