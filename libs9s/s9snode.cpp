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
#include "s9snode.h"

#include <S9sUrl>
#include <S9sVariantMap>

//#define DEBUG
//#define WARNING
#include "s9sdebug.h"

S9sNode::S9sNode()
{
}
 
S9sNode::S9sNode(
        const S9sVariantMap &properties) :
    m_properties(properties)
{
}

/**
 * \param stringRep The string representation of the host, either a JSon string
 *   or an url (e.g. "192.168.1.100:3306".
 */
S9sNode::S9sNode(
        const S9sString &stringRep)
{
    bool success;

    success = m_properties.parse(STR(stringRep));
    if (!success)
    {
        m_url = S9sUrl(stringRep);

        m_properties.clear();
        m_properties["hostname"] = m_url.hostName();

        if (m_url.hasPort())
            m_properties["port"] = m_url.port();
    }
}

S9sNode::~S9sNode()
{
}

S9sNode &
S9sNode::operator=(
        const S9sVariantMap &rhs)
{
    setProperties(rhs);
    
    return *this;
}

const S9sVariantMap &
S9sNode::toVariantMap() const
{
    return m_properties;
}

void
S9sNode::setProperties(
        const S9sVariantMap &properties)
{
    m_properties = properties;
}

/**
 * \returns the "class_name" property Cmon uses to represent the object type.
 */
S9sString
S9sNode::className() const
{
    if (m_properties.contains("class_name"))
        return m_properties.at("class_name").toString();

    return S9sString();
}

/**
 * \returns The name of the node that shall be used to represent it in user
 *   output.
 *
 * The return value might be the alias, the host name or even the IP address.
 * Currently this function is not fully implemented and it does not consider any
 * settings.
 */
S9sString
S9sNode::name() const
{
    S9sString retval;

    retval = alias();
    if (retval.empty())
        retval = hostName();

    return retval;
}

/**
 * \returns The host name, the name that used in the Cmon Configuration file to
 *   register the node.
 */
S9sString
S9sNode::hostName() const
{
    if (m_properties.contains("hostname"))
        return m_properties.at("hostname").toString();

    return S9sString();
}

S9sString
S9sNode::ipAddress() const
{
    if (m_properties.contains("ip"))
        return m_properties.at("ip").toString();

    return S9sString();
}


/**
 * \returns The alias name (or nickname) of the node if there is one, returns
 *   the empty string if not.
 */
S9sString
S9sNode::alias() const
{
    if (m_properties.contains("alias"))
        return m_properties.at("alias").toString();

    return S9sString();
}

S9sString
S9sNode::role() const
{
    if (m_properties.contains("role"))
        return m_properties.at("role").toString();

    return S9sString();
}

S9sString
S9sNode::configFile() const
{
    S9sString retval;

    if (m_properties.contains("configfile"))
    {
        S9sVariant variant = m_properties.at("configfile");

        if (variant.isVariantList())
        {
            for (uint idx = 0u; idx < variant.toVariantList().size(); ++idx)
            {
                if (!retval.empty())
                    retval += "; ";

                retval += variant.toVariantList()[idx].toString();
            }
        } else {
            variant = m_properties.at("configfile").toString();
        }
    }

    return retval;
}

S9sString
S9sNode::logFile() const
{
    if (m_properties.contains("logfile"))
        return m_properties.at("logfile").toString();

    return S9sString();
}

S9sString
S9sNode::pidFile() const
{
    if (m_properties.contains("pidfile"))
        return m_properties.at("pidfile").toString();

    return S9sString();
}

S9sString
S9sNode::dataDir() const
{
    if (m_properties.contains("datadir"))
        return m_properties.at("datadir").toString();

    return S9sString();
}

/**
 * \returns true if the node has a port number set.
 */
bool
S9sNode::hasPort() const
{
    return m_properties.contains("port");
}

/**
 * \returns the port number for the node.
 */
int
S9sNode::port() const
{
    if (m_properties.contains("port"))
        return m_properties.at("port").toInt();

    return 0;
}

/**
 * \returns The host status as a string.
 */
S9sString
S9sNode::hostStatus() const
{
    if (m_properties.contains("hoststatus"))
        return m_properties.at("hoststatus").toString();

    return S9sString();
}

S9sString
S9sNode::nodeType() const
{
    if (m_properties.contains("nodetype"))
        return m_properties.at("nodetype").toString();

    return S9sString();
}

S9sString
S9sNode::version() const
{
    if (m_properties.contains("version"))
        return m_properties.at("version").toString();

    return S9sString();
}

S9sString
S9sNode::message() const
{
    if (m_properties.contains("message"))
        return m_properties.at("message").toString();

    return S9sString();
}

S9sString
S9sNode::osVersionString() const
{
    S9sString retval;

    if (m_properties.contains("distribution"))
    {
        S9sVariantMap map = m_properties.at("distribution").toVariantMap();
        S9sString     name, release, codeName;
        
        name     = map["name"].toString();
        release  = map["release"].toString();
        codeName = map["codename"].toString();

        retval.appendWord(name);
        retval.appendWord(release);
        retval.appendWord(codeName);
    }

    return retval;
}

int
S9sNode::pid() const
{
    int retval = -1;

    if (m_properties.contains("pid"))
        retval = m_properties.at("pid").toInt();

    return retval;
}

ulonglong
S9sNode::uptime() const
{
    ulonglong retval = 0ull;

    if (m_properties.contains("uptime"))
        retval = m_properties.at("uptime").toULongLong();

    return retval;
}

/**
 * \returns true if the maintenance mode is active for the given node.
 */
bool
S9sNode::isMaintenanceActive() const
{
    if (m_properties.contains("maintenance_mode_active"))
        return m_properties.at("maintenance_mode_active").toBoolean();

    return false;
}

bool
S9sNode::readOnly() const
{
    if (m_properties.contains("readonly"))
        return m_properties.at("readonly").toBoolean();

    return false;
}

bool
S9sNode::connected() const
{
    if (m_properties.contains("connected"))
        return m_properties.at("connected").toBoolean();

    return false;
}

bool
S9sNode::managed() const
{
    if (m_properties.contains("managed"))
        return m_properties.at("managed").toBoolean();

    return false;
}

bool
S9sNode::nodeAutoRecovery() const
{
    if (m_properties.contains("node_auto_recovery"))
        return m_properties.at("node_auto_recovery").toBoolean();

    return false;
}

bool
S9sNode::skipNameResolve() const
{
    if (m_properties.contains("skip_name_resolve"))
        return m_properties.at("skip_name_resolve").toBoolean();

    return false;
}

time_t
S9sNode::lastSeen() const
{
    if (m_properties.contains("lastseen"))
        return m_properties.at("lastseen").toTimeT();

    return false;
}

int
S9sNode::sshFailCount() const
{
    if (m_properties.contains("sshfailcount"))
        return m_properties.at("sshfailcount").toInt();

    return 0;
}

/**
 * \param theList List of S9sNode objects to select from.
 * \param matchedNodes The list where the matching nodes will be placed.
 * \param otherNodes The list where non-matching nodes are placed.
 * \param protocol The protocol to select.
 *
 * This function goes through a list of nodes and selects those that have
 * matching protocol.
 */
void
S9sNode::selectByProtocol(
        const S9sVariantList &theList,
        S9sVariantList       &matchedNodes,
        S9sVariantList       &otherNodes,
        const S9sString      &protocol)
{
    S9sString protocolToFind = protocol.toLower();

    for (uint idx = 0u; idx < theList.size(); ++idx)
    {
        S9sNode   node;
        S9sString protocol;

        node     = theList[idx].toNode();
        protocol = node.protocol().toLower();

        if (protocol == protocolToFind)
            matchedNodes << node;
        else 
            otherNodes << node;
    }
}
