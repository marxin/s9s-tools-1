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
 * s9s-tools is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with s9s-tools. If not, see <http://www.gnu.org/licenses/>.
 */
#include "s9streenode.h"

//#define DEBUG
//#define WARNING
#include "s9sdebug.h"

S9sTreeNode::S9sTreeNode()
{
    m_properties["class_name"] = "CmonTreeNode";
}
 
S9sTreeNode::S9sTreeNode(
        const S9sVariantMap &properties) :
    m_properties(properties)
{
    m_properties["class_name"] = "CmonTreeNode";
}

S9sTreeNode::~S9sTreeNode()
{
}

S9sTreeNode &
S9sTreeNode::operator=(
        const S9sVariantMap &rhs)
{
    setProperties(rhs);
    
    return *this;
}

/**
 * \returns True if a property with the given key exists.
 */
bool
S9sTreeNode::hasProperty(
        const S9sString &key) const
{
    return m_properties.contains(key);
}

/**
 * \returns The value of the property with the given name or the empty
 *   S9sVariant object if the property is not set.
 */
S9sVariant
S9sTreeNode::property(
        const S9sString &name) const
{
    if (m_properties.contains(name))
        return m_properties.at(name);

    return S9sVariant();
}

/**
 * \param properties The properties to be set as a name -> value mapping.
 *
 * Sets all the properties in one step. All the existing properties will be
 * deleted, then the new properties set.
 */
void
S9sTreeNode::setProperties(
        const S9sVariantMap &properties)
{
    m_properties = properties;
}

S9sString
S9sTreeNode::name() const
{
    S9sString retval = property("item_name").toString();

    // Root node has no name, just a path.
    if (retval.empty())
        retval = property("item_path").toString();

    return retval;
}

S9sString
S9sTreeNode::path() const
{
    return property("item_path").toString();
}

S9sString
S9sTreeNode::fullPath() const
{
    S9sString retval;

    retval = path();

    if (!retval.endsWith("/"))
        retval += "/";

    retval += name();
    return retval;
}

S9sString
S9sTreeNode::spec() const
{
    return property("item_spec").toString();
}

S9sString
S9sTreeNode::linkTarget() const
{
    return property("link_target").toString();
}

S9sString
S9sTreeNode::ownerUserName() const
{
    S9sString retval;

    retval = property("owner_user_name").toString();
    if (retval.empty())
    {
        if (hasProperty("owner_user_id"))
            retval.sprintf("%d", property("owner_user_id").toInt());
    }

    return retval;
}

S9sString
S9sTreeNode::ownerGroupName() const
{
    S9sString retval;

    retval = property("owner_group_name").toString();
    if (retval.empty())
    {
        if (hasProperty("owner_group_id"))
            retval.sprintf("%d", property("owner_group_id").toInt());
    }

    return retval;
}

S9sString
S9sTreeNode::acl() const
{
    return property("item_acl").toString();
}


S9sString
S9sTreeNode::type() const
{
    return property("item_type").toString().toLower();
}

bool
S9sTreeNode::isFolder() const
{
    return type() == "folder";
}


