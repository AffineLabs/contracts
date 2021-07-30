from typing import List
from fastapi import FastAPI, Query
import uvicorn
from routes import user_portfolio, asset_info, user_trade, transactions
import sys

sys.path.append("..")

app = FastAPI()


@app.get("/")
async def root():
    return {"message": "Multiplyr BE Says: Hello World"}


# routes/user_portfolio.py


@app.get("/{user_id}/portfolio")
async def get_user_portfolio(user_id: int):
    return user_portfolio.user_portfolio(user_id)


@app.get("/{user_id}/historial_portfolio_return")
async def get_user_historical_return(user_id: int):
    return user_portfolio.historical_return(user_id)


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


# routes/trade.py

# all orders are market orders for the mvp
@app.get("/buy/{user_id}/{asset_ticker}")
async def buy_asset(user_id: int, asset_ticker: str, amount_units: float):
    return user_trade.buy_asset(user_id, asset_ticker, amount_units)


@app.get("/sell/{user_id}/{asset_ticker}")
async def sell_asset(user_id: int, asset_ticker: str, amount_units: float):
    return user_trade.sell_asset(user_id, asset_ticker, amount_units)


# routes/transactions.py


@app.get("/transactions/{user_id}/")
async def get_transactions(user_id: int, asset_tickers: List[str] = Query(["all"])):
    return transactions.user_transactions(user_id, asset_tickers)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
