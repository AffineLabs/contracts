from typing import List

from fastapi import FastAPI, Query
import uvicorn

from routes import user_portfolio, asset_info, user_trade, transactions

app = FastAPI()


@app.get("/")
async def root():
    return {"message": "Multiplyr Backend Server Says: Hello World"}


# routes/user_portfolio.py


@app.get("/{user_id}/portfolio")
async def get_user_portfolio(user_id: int):
    return user_portfolio.user_portfolio(user_id)


@app.get("/{user_id}/historical_balance")
async def get_user_historical_balance(user_id: int):
    return user_portfolio.historical_balance(user_id)


@app.get("/{user_id}/{asset_ticker}/user_asset_info")
async def get_user_asset_info(user_id: int, asset_ticker: str):
    return user_portfolio.user_asset_info(user_id, asset_ticker)


# routes/asset_info.py


@app.get("/{asset_ticker}/description")
async def get_asset_description(asset_ticker: str):
    return asset_info.asset_description(asset_ticker)


@app.get("/{asset_ticker}/historical_return")
async def get_asset_historical_return(asset_ticker: str):
    return asset_info.historical_return(asset_ticker)


@app.get("/{vault_addr}/vault_stats")
async def get_vault_status(vault_addr: str):
    return asset_info.get_vault_stats(vault_addr)


# routes/trade.py

# all orders are market orders for the mvp
@app.get("/buy/{user_id}/{asset_ticker}/{amount_units}")
async def buy_asset(user_id: int, asset_ticker: str, amount_units: float):
    return user_trade.buy_asset(user_id, asset_ticker, amount_units)


@app.get("/sell/{user_id}/{asset_ticker}/{amount_units}")
async def sell_asset(user_id: int, asset_ticker: str, amount_units: float):
    return user_trade.sell_asset(user_id, asset_ticker, amount_units)


# routes/transactions.py


@app.get("/transactions/{user_id}/")
async def get_transactions(user_id: int, asset_tickers: List[str] = Query(["all"])):
    return transactions.user_transactions(user_id, asset_tickers)


def run():
    uvicorn.run("scripts.main:app", host="0.0.0.0", port=8000, reload=True)


if __name__ == "__main__":
    run()
