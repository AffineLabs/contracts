from utils import utils


def historical_balance(user_id: int):
    """
    get historical return for the user with user_id
    """
    if not utils.is_valid_user_id(user_id):
        return utils.user_id_error_response(user_id)
    user_historical_balance_df = utils.get_user_balance_from_sql(user_id)
    return {
        "userId": user_id,
        "historicalBalance": dict(
            zip(
                user_historical_balance_df["timestamp"],
                user_historical_balance_df["user_balance"],
            )
        ),
    }


def user_public_address(user_id: int):
    if not utils.is_valid_user_id(user_id) or user_id != 1:
        return utils.user_id_error_response(user_id)
    return {"userId": user_id, "publicAddress": "0xfakeaddr"}
