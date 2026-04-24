/**
 * kuzu-wasm.d.ts — Ambient type declaration for kuzu-wasm@0.11.3.
 *
 * kuzu-wasm ships no TypeScript types. This declaration provides the minimal
 * surface needed by store.browser.ts. The types are derived from the JSDoc
 * comments in node_modules/kuzu-wasm/index.js and confirmed by S2.1/S2.3.
 *
 * Key API facts (S2.1 findings):
 *   - conn.query() returns QueryResult (not an array)
 *   - Use qr.getAllObjects() (not qr.getAll())
 *   - FS is a singleton instance (not a constructor)
 *   - setWorkerPath() must be called before any DB operation
 */

declare module 'kuzu-wasm' {
  /** A query result handle. Must be closed after use. */
  class QueryResult {
    /** Returns all rows as plain objects. kuzu-wasm@0.11.3 browser variant. */
    getAllObjects(): Promise<Record<string, unknown>[]>;
    /** Close this query result handle (TC9). */
    close(): Promise<void>;
    hasNextQueryResult(): boolean;
    getNextQueryResult(): Promise<QueryResult>;
  }

  /** An open database connection. */
  class Connection {
    constructor(database: Database);
    query(cypher: string): Promise<QueryResult>;
    close(): Promise<void>;
  }

  /** A kuzu database. */
  class Database {
    constructor(path: string);
    close(): Promise<void>;
  }

  /** Emscripten FS wrapper (singleton instance). */
  interface FSInstance {
    mkdir(path: string): Promise<void>;
    mountIdbfs(path: string): Promise<void>;
    unmount(path: string): Promise<void>;
    /**
     * Sync IDBFS.
     * @param populate true = load from IDB into FS; false = flush FS to IDB.
     */
    syncfs(populate: boolean): Promise<void>;
    readFile(path: string): Promise<Buffer>;
    writeFile(path: string, data: Buffer | string): Promise<void>;
    unlink(path: string): Promise<void>;
    readDir(path: string): Promise<string[]>;
    stat(path: string): Promise<Record<string, unknown>>;
  }

  /** The kuzu-wasm module default export. */
  const kuzu: {
    Database: typeof Database;
    Connection: typeof Connection;
    QueryResult: typeof QueryResult;
    FS: FSInstance;
    setWorkerPath(path: string): void;
    init(): Promise<void>;
    getVersion(): Promise<string>;
    getStorageVersion(): Promise<bigint>;
    close(): Promise<void>;
  };

  export default kuzu;
}
