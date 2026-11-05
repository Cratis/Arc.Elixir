// Copyright (c) Cratis. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { AuthenticationQueriesPage } from '../../lib/samples/authentication_queries/AuthenticationQueriesPage';
import { ChangeStreamPage } from '../../lib/samples/change_stream/ChangeStreamPage';
import { ConditionalQueriesPage } from '../../lib/samples/query_showcase/ConditionalQueriesPage';
import { CrossCuttingAuthorizationPage } from '../../lib/samples/cross_cutting_authorization/CrossCuttingAuthorizationPage';
import { LiveFeedPage } from '../../lib/samples/live_feed/LiveFeedPage';
import { MongoWatcherPage } from '../../lib/samples/mongo_watcher/MongoWatcherPage';
import { ObservableCollectionPage } from '../../lib/samples/observable_collection/ObservableCollectionPage';
import { ObservableCollectionWithGuidPage } from '../../lib/samples/observable_collection_with_guid/ObservableCollectionWithGuidPage';
import { QueryShowcasePage } from '../../lib/samples/query_showcase/QueryShowcasePage';
import { TickerPage } from '../../lib/samples/ticker/TickerPage';

export const pages = {
    authenticationqueries: { title: 'Authentication Queries', component: AuthenticationQueriesPage },
    crosscuttingauthorization: { title: 'Cross-Cutting Authorization', component: CrossCuttingAuthorizationPage },
    ticker: { title: 'Ticker', component: TickerPage },
    livefeed: { title: 'Live Feed', component: LiveFeedPage },
    queryshowcase: { title: 'Query Showcase', component: QueryShowcasePage },
    conditionalqueries: { title: 'Conditional Queries', component: ConditionalQueriesPage },
    changestream: { title: 'Change Stream', component: ChangeStreamPage },
    observablecollection: { title: 'Observable Collection', component: ObservableCollectionPage },
    observablecollectionwithguid: { title: 'Observable Collection With Guid', component: ObservableCollectionWithGuidPage },
    mongodb: { title: 'MongoDB', component: MongoWatcherPage }
} as const;

export type Page = keyof typeof pages;

interface AppProps {
    title: string;
    page: Page;
    onPageChange: (page: Page) => void;
}

/**
 * Root application component with simple tab navigation.
 */
export const App = ({ title, page, onPageChange }: AppProps) => {
    const Current = pages[page].component;

    return (
        <div style={{ fontFamily: 'sans-serif', maxWidth: 1000, margin: '0 auto', padding: 24 }}>
            <h1>{title}</h1>
            <nav style={{ display: 'flex', gap: 12, marginBottom: 24, flexWrap: 'wrap' }}>
                {(Object.keys(pages) as Page[]).map(key => (
                    <button key={key} onClick={() => onPageChange(key)} style={{ fontWeight: page === key ? 'bold' : 'normal' }}>
                        {pages[key].title}
                    </button>
                ))}
            </nav>
            <Current />
        </div>
    );
};
