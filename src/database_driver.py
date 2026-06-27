import asyncpg
import os
from dotenv import load_dotenv

load_dotenv()

class DatabaseDriver:
    def __init__(self):
        self.url = str(os.getenv("DATABASE_URL"))
        self.pool = None
    
    async def connect(self):
        print(f"Connecting with URL: {self.url}")  # add this
        self.pool = await asyncpg.create_pool(self.url, max_size = 20)
        print("DB connected successfully ✅")
    
    
    # FOR SELECT
    async def fetch(self, query, *args, user_id=None):
        async with self.pool.acquire() as connection:
            if user_id:
                await connection.execute(f"SELECT set_config('myapp.user_id', $1, false)", str(user_id))            
            result = await connection.fetch(query, *args)
            
            return result
    
    #FOR UPDATE, INSERT, DELETE
    
    async def execute(self, query, *args, user_id=None):
        async with self.pool.acquire() as connection:
            if user_id:
                await connection.execute(f"SELECT set_config('myapp.user_id', $1, false)", str(user_id))            
            
            await connection.execute(query, *args)



            