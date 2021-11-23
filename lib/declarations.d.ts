declare module "resin-discoverable-services" {
    type Callback<T> = (error?: Error, result?: T) => void;

    export interface PublishOptions {
        identifier: string;
        name: string;
        host?: string;
        port: number;
    }

	export interface ServiceDefinition {
		service: string;
		tags: string[];
	}

	export interface ServiceInformation {
		addresses: string[];
		name: string;
		fqdn: string;
		host: string;
		port: number;
		type: string;
		protocol: string;
		subtypes: string[];
		txt: any;
		referer: {
			address: string;
			family: string;
			port: number;
		}
	}

    export function setRegistryPath(path: string): void;
    export function enumerateServices(callback?: Callback<string[]>): Promise<ServiceDefinition[]>;
    export function findServices(services: string[], timeout?: number, callback?: Callback<ServiceInformation[]>): Promise<ServiceInformation[]>;
    export function publishServices(services: PublishOptions[], callback?: Callback<void>): Promise<void>;
}
