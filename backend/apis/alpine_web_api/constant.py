import pydantic
import fastapi

# using camel case for param names for consistency with javascript

API_VERSION = "0.3.0"
API_DESC = f"""
Welcome to Alpine Web API v{API_VERSION}!

## Changelog
### v 1.0.0
- Removed `getUserPublicAddress`
- Added `updateUserProfile`, which can be used to create a new user profile, 
  and update user's public address.
- Removed vault address and abi from `getAllVaultMetadata`, and added `vaultTVL` 
(total value locked).
- Added `assetType` and `currentPercentage` in the asset comp. of the vault.

### v 0.2.0
- Added an `apy` field for `getAssetMetadata` and for the `alpSave` vault. 
- Added fields `vaultAddress` and `vaultAbi` for the usdc smart contract. This is needed to know idle
  cash amount in a user's wallet.
- added a real user public address
"""


USER_ID_QUERY = fastapi.Query(..., description="internal user id", title="user id")
ASSET_TICKER_QUERY = fastapi.Query(
    ..., description="case insensitive asset ticker", title="user id"
)


class UserProfile(pydantic.BaseModel):
    email: str = pydantic.Field(
        ..., description="a valid email address", title="user email"
    )
    userId: int = pydantic.Field(None, description="user id", title="user id")
    publicAddress: str = pydantic.Field(
        None, description="user's public address", title="public address"
    )
    isOnboarded: bool = pydantic.Field(
        False,
        description="whether the user has been onboarded, default is false.",
        title="is onboarded",
    )

    class Config:
        schema_extra = {
            "example": {
                "email": "user@tryalpine.com",
                "userId": 1,
                "publicAddress": "0xfakeaddr",
                "isOnboarded": False,
            }
        }
