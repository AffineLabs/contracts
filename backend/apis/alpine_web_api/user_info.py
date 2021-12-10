from . import utils, constant


def get_historical_balance(user_id: int):
    """
    get historical return for the user with user_id
    """
    if not utils.is_valid_user_id(user_id):
        return utils.user_id_error_response(user_id)
    # for the mock response from db
    user_historical_balance_df = utils.get_user_balance_from_sql(user_id=1)
    return {
        "userId": user_id,
        "historicalBalance": dict(
            zip(
                user_historical_balance_df["timestamp"].dt.strftime(
                    "%Y-%m-%d %H:%M:%S"
                ),
                user_historical_balance_df["user_balance"],
            )
        ),
    }


def get_user_public_address(user_id: int):
    if not utils.is_valid_user_id(user_id) or user_id != 1:
        return utils.user_id_error_response(user_id)
    return {
        "userId": user_id,
        "publicAddress": "0x69b3ce79B05E57Fc31156fEa323Bd96E6304852D",
    }


def update_user_profile(profile: constant.UserProfile):
    return profile
