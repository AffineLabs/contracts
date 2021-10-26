from typing import List

from fastapi import FastAPI, Query
import uvicorn
import sys

sys.path.append("..")

from routes import user_portfolio, asset_info

app = FastAPI()


@app.get("/")
async def root():
    return {"message": "Alpine Backend Server Says: Hello World"}


# routes/user_portfolio.py


@app.get("/{user_id}/historical_balance")
async def get_user_historical_balance(user_id: int):
    return user_portfolio.historical_balance(user_id)


@app.get("/{user_id}/pubkey")
async def get_user_public_address(user_id: int):
    """
    get public address of the user. For now, if the
    user id is 1, returns a fake address, otherwise
    returns an error messge
    """
    return user_portfolio.user_public_address(user_id)


# routes/asset_info.py


@app.get("/{asset_ticker}/description")
async def get_asset_description(asset_ticker: str):
    return asset_info.asset_description(asset_ticker)


@app.get("/{asset_ticker}/historical_price")
async def get_asset_historical_price(asset_ticker: str):
    return asset_info.historical_price(asset_ticker)


# routes/trade.py

# all orders are market orders for the mvp
# @app.get("/buy/{user_id}/{asset_ticker}/{amount_units}")
# async def buy_asset(user_id: int, asset_ticker: str, amount_units: float):
#     return user_trade.buy_asset(user_id, asset_ticker, amount_units)


# @app.get("/sell/{user_id}/{asset_ticker}/{amount_units}")
# async def sell_asset(user_id: int, asset_ticker: str, amount_units: float):
#     return user_trade.sell_asset(user_id, asset_ticker, amount_units)


# # routes/transactions.py
# @app.get("/transactions/{user_id}/")
# async def get_transactions(user_id: int, asset_tickers: List[str] = Query(["all"])):
#     return transactions.user_transactions(user_id, asset_tickers)


# @app.get("/{user_id}/withdraw")
# async def user_withdraw(user_id: int):
#     return transactions.withdraw(user_id)


def run():
    uvicorn.run("scripts.main:app", host="0.0.0.0", port=8000, reload=True)


if __name__ == "__main__":
    run()
