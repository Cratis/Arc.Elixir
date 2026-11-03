// Copyright (c) Cratis. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import assert from "node:assert/strict";
import { test } from "node:test";
import { EventSource as NodeEventSource } from "eventsource";
import { Globals } from "@cratis/arc";
import {
    QueryHttpMethod,
    type QueryResult,
    QueryTransportMethod,
    resetSharedMultiplexer,
    SortDirection,
    Sorting,
    Paging,
} from "@cratis/arc/queries";
import { IdentityProvider } from "@cratis/arc/identity";
import { Guid } from "@cratis/fundamentals";
import { Details } from "../generated/Identity";
import { AllAuthors, ById, LiveAuthors } from "../generated/Authors/Listing";
import { RegisterAuthor, RenameAuthor } from "../generated/Authors/Registration";

const origin = process.env.ARC_ELIXIR_ORIGIN;
if (!origin) {
    throw new Error("ARC_ELIXIR_ORIGIN must identify the running Arc for Elixir contract server.");
}

Globals.origin = origin;
Globals.apiBasePath = "";
Globals.queryHttpMethod = QueryHttpMethod.Get;
Globals.queryDirectMode = false;
Globals.queryTransportMethod = QueryTransportMethod.WebSocket;
Globals.queryCacheRetentionMs = 0;
// SAFETY: the Node eventsource implementation provides the browser EventSource surface used by Arc.
Globals.eventSourceFactory = (url) => new NodeEventSource(url) as unknown as EventSource;

function clientPrincipal(): Record<string, string> {
    const principal = {
        identityProvider: "aad",
        userId: "alice@contoso.com",
        userDetails: "Alice",
        userRoles: ["editor"],
        claims: [{ typ: "department", val: "Engineering" }],
    };
    return { "x-ms-client-principal": Buffer.from(JSON.stringify(principal)).toString("base64") };
}

function waitFor<T>(register: (resolve: (value: T) => void) => () => void, timeoutMs = 8000): Promise<T> {
    return new Promise<T>((resolve, reject) => {
        let unsubscribe: () => void = () => undefined;
        const timer = setTimeout(() => {
            unsubscribe();
            reject(new Error("Timed out waiting for the observable query."));
        }, timeoutMs);
        unsubscribe = register((value) => {
            clearTimeout(timer);
            unsubscribe();
            resolve(value);
        });
    });
}

test("Arc for Elixir serves the generated proxies", async (t) => {
    await t.test("a command executes and echoes the correlation id", async () => {
        const command = new RegisterAuthor();
        command.id = Guid.create();
        command.name = "Grace";

        const result = await command.execute();

        assert.equal(result.isSuccess, true, JSON.stringify(result));
        assert.equal(result.isAuthorized, true);
        assert.match(String(result.correlationId), /^[0-9a-f-]{36}$/);
    });

    await t.test("the client validator rejects before the network", async () => {
        const command = new RegisterAuthor();
        command.id = Guid.create();
        command.name = "a name that is far too long";

        const result = await command.execute();

        assert.equal(result.isValid, false);
        assert.ok(result.validationResults.some((v) => v.members.includes("name")));
    });

    await t.test("the server validates what the client could not", async () => {
        const command = new RegisterAuthor();
        command.id = Guid.create();
        command.name = "forbidden";

        const result = await command.execute();

        assert.equal(result.isValid, false);
        assert.equal(result.validationResults[0]?.message, "That name is not allowed.");
    });

    await t.test("an anonymous caller is not authorized for a role-protected command", async () => {
        const command = new RenameAuthor();
        command.id = Guid.create();
        command.name = "Grace";

        const result = await command.execute();

        assert.equal(result.isAuthorized, false);
        assert.equal(result.isSuccess, false);
    });

    await t.test("a query returns hydrated models", async () => {
        const result = await new AllAuthors().perform();

        assert.equal(result.isSuccess, true, JSON.stringify(result));
        assert.ok(result.data.length >= 3);
        assert.equal(typeof result.data[0].name, "string");
    });

    await t.test("a query with an argument returns one model", async () => {
        const result = await new ById().perform({ id: Guid.parse("7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e") });

        assert.equal(result.isSuccess, true, JSON.stringify(result));
        assert.equal(result.data.name, "Ada");
    });

    await t.test("paging and sorting reach the server", async () => {
        const query = new AllAuthors();
        query.paging = new Paging(0, 2);
        query.sorting = new Sorting("name", SortDirection.descending);
        const result = await query.perform();

        assert.equal(result.isSuccess, true, JSON.stringify(result));
        assert.equal(result.data.length, 2);
        assert.equal(result.paging.size, 2);
        assert.ok(result.paging.totalItems >= 3);
    });

    await t.test("the HTTP QUERY method is used when requested", async () => {
        Globals.queryHttpMethod = QueryHttpMethod.Query;
        try {
            const result = await new AllAuthors().perform();
            assert.equal(result.isSuccess, true, JSON.stringify(result));
        } finally {
            Globals.queryHttpMethod = QueryHttpMethod.Get;
        }
    });

    await t.test("an observable query pushes updates over the WebSocket hub", async () => {
        resetSharedMultiplexer();
        const query = new LiveAuthors();
        const seen: number[] = [];

        const second = new Promise<QueryResult<unknown[]>>((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error("No update was pushed.")), 8000);
            const subscription = query.subscribe((result: QueryResult<unknown[]>) => {
                seen.push(result.data.length);
                if (seen.length === 1) {
                    void fetch(`${origin}/test/add-author?name=Live`);
                }
                if (seen.length >= 2 && result.data.length > seen[0]) {
                    clearTimeout(timer);
                    subscription.unsubscribe();
                    resolve(result);
                }
            });
        });

        const result = await second;
        assert.ok(result.data.length > seen[0]);
    });

    await t.test("an observable query uses the direct SSE transport", async () => {
        resetSharedMultiplexer();
        Globals.queryTransportMethod = QueryTransportMethod.ServerSentEvents;
        Globals.queryDirectMode = true;
        try {
            const result = await waitFor<QueryResult<unknown[]>>((resolve) => {
                const subscription = new LiveAuthors().subscribe((r: QueryResult<unknown[]>) => resolve(r));
                return () => subscription.unsubscribe();
            });
            assert.ok(result.data.length >= 3);
        } finally {
            Globals.queryTransportMethod = QueryTransportMethod.WebSocket;
            Globals.queryDirectMode = false;
        }
    });

    await t.test("an anonymous caller has no identity", async () => {
        IdentityProvider.clearCache();
        IdentityProvider.setOrigin(origin);
        IdentityProvider.setApiBasePath("");
        IdentityProvider.setHttpHeadersCallback(() => ({}));

        const identity = await IdentityProvider.getCurrent(Details);

        assert.equal(identity.isSet, false);
    });

    await t.test("a signed-in caller gets a typed identity with roles and details", async () => {
        IdentityProvider.clearCache();
        IdentityProvider.setHttpHeadersCallback(clientPrincipal);

        const identity = await IdentityProvider.getCurrent(Details);

        assert.equal(identity.isSet, true);
        assert.equal(identity.name, "Alice");
        assert.equal(identity.isInRole("editor"), true);
        assert.equal(identity.isInRole("admin"), false);
        assert.ok(identity.details instanceof Details);
        assert.equal(identity.details.displayName, "Hello Alice");
        assert.equal(identity.details.department, "Engineering");
    });

    await t.test("the identity endpoint answers 401 anonymously and is private", async () => {
        const anonymous = await fetch(`${origin}/.cratis/me`);
        const signedIn = await fetch(`${origin}/.cratis/me`, { headers: clientPrincipal() });

        assert.equal(anonymous.status, 401);
        assert.equal(signedIn.status, 200);
        assert.equal(signedIn.headers.get("cache-control"), "no-store, private");
        const body = (await signedIn.json()) as Record<string, unknown>;
        assert.deepEqual(Object.keys(body).sort(), ["details", "id", "isAuthenticated", "isAuthorized", "name", "roles"]);
    });

    await t.test("development users and tenants are listed for tools such as Lens", async () => {
        const users = (await (await fetch(`${origin}/.cratis/users`)).json()) as Array<{ microsoftIdentity: { userId: string } }>;
        const tenants = (await (await fetch(`${origin}/.cratis/tenants`)).json()) as Array<{ id: string }>;

        assert.equal(users[0]?.microsoftIdentity.userId, "ada@example.com");
        assert.equal(tenants[0]?.id, "acme");
    });
});
