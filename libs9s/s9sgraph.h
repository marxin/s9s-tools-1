/* 
 * Copyright (C) 2011-2017 severalnines.com
 */
#pragma once

#include "S9sVariant"
#include "S9sVariantList"
#include <vector>

class S9sGraph
{
    public:
        enum AggregateType 
        {
            Max,
            Min,
            Average
        };

        S9sGraph();
        virtual ~S9sGraph();

        void setAggregateType(S9sGraph::AggregateType type);

        void appendValue(const S9sVariant &value);
        void setTitle(const S9sString &title);

        int nValues() const;
        S9sVariant max() const;

        void realize();
        void print() const;

    protected:
        void transform(int newWidth, int newHeight);
        void createLines(int newWidth, int newHeight);

        const char *yLabelFormat() const;

    private:
        S9sVariant aggregate(const S9sVariantList &data) const;

    private:
        AggregateType   m_aggregateType;
        S9sVariantList  m_rawData;
        S9sVariantList  m_transformed;
        int             m_width, m_height;
        S9sVariantList  m_lines;
        S9sString       m_title;
};
