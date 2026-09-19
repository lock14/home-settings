/**
 * Solarized Dark syntax preview for TypeScript.
 * Demonstrates interfaces, types, generics, classes, enums, and async/await.
 */

export enum UserRole {
  Admin = "ADMIN",
  Developer = "DEVELOPER",
  Guest = "GUEST",
}

export type ConnectionState = "connected" | "connecting" | "disconnected";

export interface ApiResponse<T> {
  readonly success: boolean;
  readonly payload: T;
  readonly latencyMs: number;
  readonly timestamp: Date;
  error?: string;
}

export interface UserProfile {
  id: string;
  username: string;
  role: UserRole;
  quotaBytes: number;
  isActive: boolean;
  attributes?: Record<string, string | number>;
}

export class ServiceGateway<T extends { id: string }> {
  protected readonly baseUrl: string;
  private connectionState: ConnectionState = "disconnected";

  constructor(
    public readonly serviceName: string,
    public readonly port: number = 8080,
    baseUrl: string = "https://api.internal/v2"
  ) {
    this.baseUrl = baseUrl;
  }

  public async request(endpoint: string): Promise<ApiResponse<T>> {
    this.connectionState = "connecting";
    const requestUrl = `${this.baseUrl}/${endpoint}?service=${encodeURIComponent(this.serviceName)}`;

    try {
      // Simulated asynchronous network latency
      await new Promise((resolve) => setTimeout(resolve, 50));
      this.connectionState = "connected";

      const mockData = { id: "usr-42", username: "alex", role: UserRole.Developer } as unknown as T;

      return {
        success: true,
        payload: mockData,
        latencyMs: 12.5,
        timestamp: new Date(),
      };
    } catch (err: unknown) {
      this.connectionState = "disconnected";
      const message = err instanceof Error ? err.message : "Unknown gateway fault";
      throw new Error(`[Gateway: ${this.serviceName}] Failed request to ${requestUrl}: ${message}`);
    }
  }

  public getState(): ConnectionState {
    return this.connectionState;
  }
}
