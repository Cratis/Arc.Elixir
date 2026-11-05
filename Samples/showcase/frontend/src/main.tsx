// Copyright (c) Cratis. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { Arc, ArcContext } from '@cratis/arc.react';
import { useIdentity } from '@cratis/arc.react/identity';
import { ObservableQueryTransferMode } from '@cratis/arc';
import { QueryTransportMethod } from '@cratis/arc/queries';
import { StrictMode, useContext, useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { App, type Page } from './App';
import { IdentityDetails } from '../../lib/samples/identity';

// The sign-in and the tenant are kept twice: as headers, which every HTTP request carries, and as
// cookies, which is all a WebSocket handshake or an EventSource can send. The server's
// `Samples.Web.CookieIdentity` plug turns the cookies back into the headers Arc reads.
const principalHeader = (userId: string, userName: string, roles: string): string =>
    btoa(JSON.stringify({
        identityProvider: 'demo',
        userId,
        userDetails: userName,
        userRoles: roles.split(',').map(role => role.trim()).filter(role => role),
        claims: []
    }));

const setCookie = (name: string, value: string | null): void => {
    document.cookie = value
        ? `${name}=${value}; path=/; SameSite=Lax`
        : `${name}=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT`;
};

/**
 * Bridges changes of who is signed in, and of the tenant, into Arc: the identity is read again and
 * the query connections are opened again, so they carry the new cookies.
 */
const AuthBridge = ({ signature }: { signature: string }) => {
    const arc = useContext(ArcContext);
    const identity = useIdentity<IdentityDetails>(IdentityDetails);
    const first = useRef(true);

    useEffect(() => {
        if (first.current) {
            first.current = false;
            return;
        }
        identity.refresh();
        arc.reconnectQueries?.();
    }, [signature]);

    return null;
};

const Root = () => {
    const [transport, setTransport] = useState<QueryTransportMethod>(QueryTransportMethod.WebSocket);
    const [connectionCount, setConnectionCount] = useState(1);
    const [directMode, setDirectMode] = useState(false);
    const [transferMode, setTransferMode] = useState<ObservableQueryTransferMode>(ObservableQueryTransferMode.Delta);
    const [loggedIn, setLoggedIn] = useState(false);
    const [userId, setUserId] = useState('demo-user');
    const [userName, setUserName] = useState('Demo User');
    const [roles, setRoles] = useState('User');
    const [tenant, setTenant] = useState('');
    const [configKey, setConfigKey] = useState(0);
    const [page, setPage] = useState<Page>('authenticationqueries');

    // Settings that change how connections are made need a new Arc context.
    const reconfigure = (change: () => void) => {
        change();
        setConfigKey(key => key + 1);
    };

    useEffect(() => {
        setCookie('x-ms-client-principal', loggedIn ? principalHeader(userId, userName, roles) : null);
        setCookie('x-cratis-tenant-id', tenant || null);
    }, [loggedIn, userId, userName, roles, tenant]);

    const httpHeadersCallback = (): Record<string, string> => {
        const headers: Record<string, string> = {};
        if (loggedIn) {
            headers['x-ms-client-principal-id'] = userId;
            headers['x-ms-client-principal-name'] = userName;
            headers['x-ms-client-principal'] = principalHeader(userId, userName, roles);
        }
        if (tenant) {
            headers['x-cratis-tenant-id'] = tenant;
        }
        return headers;
    };

    const label: React.CSSProperties = { display: 'flex', alignItems: 'center', gap: 4 };

    return (
        <StrictMode>
            <div style={{ padding: '8px 16px', background: '#f0f0f0', borderBottom: '1px solid #ccc', display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap', fontFamily: 'sans-serif', fontSize: 13 }}>
                <label style={label}>
                    Transport
                    <select value={transport} onChange={event => reconfigure(() => setTransport(event.target.value as QueryTransportMethod))}>
                        <option value={QueryTransportMethod.WebSocket}>WebSocket</option>
                        <option value={QueryTransportMethod.ServerSentEvents}>Server-Sent Events</option>
                    </select>
                </label>
                <label style={label}>
                    Connections
                    <button onClick={() => reconfigure(() => setConnectionCount(count => Math.max(1, count - 1)))}>−</button>
                    <span style={{ minWidth: 20, textAlign: 'center' }}>{connectionCount}</span>
                    <button onClick={() => reconfigure(() => setConnectionCount(count => Math.min(10, count + 1)))}>+</button>
                </label>
                <label style={label}>
                    <input type="checkbox" checked={directMode} onChange={event => reconfigure(() => setDirectMode(event.target.checked))} />
                    Direct mode
                </label>
                <label style={label}>
                    Transfer mode
                    <select value={transferMode} onChange={event => reconfigure(() => setTransferMode(event.target.value as ObservableQueryTransferMode))}>
                        <option value={ObservableQueryTransferMode.Delta}>Delta</option>
                        <option value={ObservableQueryTransferMode.Full}>Full</option>
                    </select>
                </label>
                <label style={label}>
                    Tenant
                    <select value={tenant} onChange={event => setTenant(event.target.value)}>
                        <option value="">Default</option>
                        <option value="acme">acme</option>
                        <option value="globex">globex</option>
                    </select>
                </label>
                <label style={label}>
                    <input type="checkbox" checked={loggedIn} onChange={event => setLoggedIn(event.target.checked)} />
                    Logged in
                </label>
                <label style={label}>
                    User ID <input value={userId} onChange={event => setUserId(event.target.value)} style={{ width: 90 }} />
                </label>
                <label style={label}>
                    Name <input value={userName} onChange={event => setUserName(event.target.value)} style={{ width: 90 }} />
                </label>
                <label style={label}>
                    Roles <input value={roles} onChange={event => setRoles(event.target.value)} style={{ width: 160 }} />
                </label>
            </div>
            <Arc
                development={true}
                key={configKey}
                queryTransportMethod={transport}
                queryConnectionCount={connectionCount}
                queryDirectMode={directMode}
                observableQueryTransferMode={transferMode}
                httpHeadersCallback={httpHeadersCallback}
            >
                <AuthBridge signature={`${loggedIn}|${userId}|${userName}|${roles}|${tenant}`} />
                <App title="Arc for Elixir showcase" page={page} onPageChange={setPage} />
            </Arc>
        </StrictMode>
    );
};

createRoot(document.getElementById('root')!).render(<Root />);
