// Copyright (c) Cratis. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { Arc } from '@cratis/arc.react';
import { StrictMode, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';

// The demo sign-in of the Phoenix sample: the backend reads these headers (see Library.Web.DevAuth).
// A real application authenticates with its own scheme and Arc reads the resulting principal.
const identities: Record<string, Record<string, string>> = {
    anonymous: {},
    ada: { 'x-demo-user': 'ada' },
    editor: { 'x-demo-user': 'ed', 'x-demo-roles': 'editor' }
};

const Root = () => {
    const [who, setWho] = useState('anonymous');

    return (
        <StrictMode>
            <label>
                Signed in as{' '}
                <select value={who} onChange={event => setWho(event.target.value)}>
                    {Object.keys(identities).map(name => (
                        <option key={name} value={name}>{name}</option>
                    ))}
                </select>
            </label>
            {/* A new Arc context per identity: a query captures the credentials it was created with. */}
            <Arc key={who} development={true} httpHeadersCallback={() => identities[who]}>
                <App />
            </Arc>
        </StrictMode>
    );
};

createRoot(document.getElementById('root')!).render(<Root />);
