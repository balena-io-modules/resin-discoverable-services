declare module "resin-discoverable-services" {
    export interface publishOptions {
        identifier: string;
        name: string;
        host?: string;
        port: number;
    }

    export function setRegistryPath(path: string): void;
    export function enumerateServices(callback?: (error: Error, results: [string]) => void): Promise<[string]>;
    export function findServices(services: [string], timeout?: number, callback?: (error: Error, results: [string]) => void): Promise<[string]>;
    export function publishServices(services: [publishOptions], callback?: (error: Error) => void): Promise<void>;
}
