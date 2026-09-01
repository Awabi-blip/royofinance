from glide import GlideClient, GlideClientConfiguration, NodeAddress
import asyncio

class ValkeyDriver:

    def __init__(self):
        self.config = GlideClientConfiguration(
        addresses=[NodeAddress("localhost", 6379)],
        database_id=0,
    )

    async def connect(self):
        self.client = await GlideClient.create(self.config)
        print("KV connected successfully ✅")

    def get_client(self):
        return self.client


