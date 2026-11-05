// Copyright (c) Cratis. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { useState } from 'react';
import { AddWatcherItem, AddWatcherNote } from '.';
import { WatchAll as WatchAllItems, ObserveAll as ObserveAllItems } from './items';
import { WatchAll as WatchAllNotes } from './notes';

/**
 * Page for the MongoDB integration.
 *
 * Each tenant is a database of its own: pick another tenant in the toolbar and the same queries and
 * commands read and write another database. The queries are observable, driven by one MongoDB change
 * stream per database. `WatchAll` re-runs when items **or notes** change; `ObserveAll` only when
 * items do, so adding a note moves the first list and leaves the second where it was.
 *
 * It needs a MongoDB replica set: `docker compose up -d` in the sample folder.
 */
export const MongoWatcherPage = () => {
    const [name, setName] = useState('');
    const [text, setText] = useState('');
    const [message, setMessage] = useState('');
    const [watchAll] = WatchAllItems.use();
    const [observeAll] = ObserveAllItems.use();
    const [notes] = WatchAllNotes.use();

    const addItem = async () => {
        const command = new AddWatcherItem();
        command.name = name;
        const result = await command.execute();
        setMessage(result.isSuccess ? '' : describe(result));
        if (result.isSuccess) setName('');
    };

    const addNote = async () => {
        const command = new AddWatcherNote();
        command.text = text;
        const result = await command.execute();
        setMessage(result.isSuccess ? '' : describe(result));
        if (result.isSuccess) setText('');
    };

    return (
        <div>
            <h2>MongoDB</h2>
            <p>
                Documents live in MongoDB, in the database of the selected tenant. The queries are observable:
                a change stream tells them when to run again. Run <code>docker compose up -d</code> for a
                replica set.
            </p>
            {message && <p role="alert" style={{ color: '#a00' }}>{message}</p>}

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 24 }}>
                <section>
                    <h3>Items (WatchAll)</h3>
                    <p style={{ fontSize: 13, color: '#555' }}>Re-runs when items or notes change.</p>
                    <form onSubmit={event => { event.preventDefault(); void addItem(); }}>
                        <input value={name} onChange={event => setName(event.target.value)} placeholder="Item name" />{' '}
                        <button type="submit" disabled={!name}>Add item</button>
                    </form>
                    <List state={watchAll} text={item => item.name} />
                </section>
                <section>
                    <h3>Items (ObserveAll)</h3>
                    <p style={{ fontSize: 13, color: '#555' }}>Re-runs only when items change.</p>
                    <List state={observeAll} text={item => item.name} />
                </section>
                <section>
                    <h3>Notes (WatchAll)</h3>
                    <p style={{ fontSize: 13, color: '#555' }}>Re-runs when notes or items change.</p>
                    <form onSubmit={event => { event.preventDefault(); void addNote(); }}>
                        <input value={text} onChange={event => setText(event.target.value)} placeholder="Note" />{' '}
                        <button type="submit" disabled={!text}>Add note</button>
                    </form>
                    <List state={notes} text={note => note.text} />
                </section>
            </div>
        </div>
    );
};

const describe = (result: { exceptionMessages: string[]; validationResults: { message: string }[] }) =>
    [...result.exceptionMessages, ...result.validationResults.map(validation => validation.message)].join(' ') ||
    'The command failed.';

interface Identified { id: { toString(): string } }

const List = <T extends Identified>({ state, text }: {
    state: { isPerforming: boolean; isSuccess: boolean; hasData: boolean; data: T[]; exceptionMessages: string[] };
    text: (item: T) => string;
}) => {
    if (state.isPerforming && !state.hasData) return <p>Connecting…</p>;
    if (state.exceptionMessages.length > 0) return <p style={{ color: '#a00' }}>{state.exceptionMessages.join(' ')}</p>;
    return (
        <ul>
            {state.data.map(item => <li key={item.id.toString()}>{text(item)}</li>)}
            {state.data.length === 0 && <li style={{ color: '#888' }}>Nothing yet</li>}
        </ul>
    );
};
