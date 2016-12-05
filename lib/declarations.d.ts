declare module "resin-discoverable-services" {
    type Callback<T> = (error?: Error, result?: T) => void;

    export interface PublishOptions {
        identifier: string;
        name: string;
        host?: string;
        port: number;
    }

    export function setRegistryPath(path: string): void;
    export function enumerateServices(callback?: Callback<string[]>): Promise<string[]>;
    export function findServices(services: string[], timeout?: number, callback?: Callback<string[]>): Promise<string[]>;
    export function publishServices(services: PublishOptions[], callback?: Callback<void>): Promise<void>;
}
