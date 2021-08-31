import pandas as pd
import numpy as np
import pandas as pd
from datetime import datetime
import logging
from sklearn.linear_model import LinearRegression


def merge_dfs(dfs, return_col, take_rolling_mean=False):
    """
    merge return cols of dfs based on index column. take rolling
    mean of 7 days and return the resulting df
    """
    merged_df = None
    for name, df in dfs.items():
        df = df.rename(columns={f"{return_col}": name})[[name]]
        merged_df = (
            df
            if merged_df is None
            else pd.merge(merged_df, df, left_index=True, right_index=True, how="inner")
        )
    if take_rolling_mean:
        merged_df = merged_df.rolling(7, min_periods=1).mean()
    return merged_df


def impute_data(X, y, start_date, end_date):
    """
    impute the data for asset y using X (btc, eth and stable coin prices)
    train on the period of available data, then predict on the data until
    the start date.

    X : pd Dataframe of feature columns, datetime as index
    y: pd Dataframe with one target column, datetime as index
    start_date: start date for the dataset after the data has been imputed
    end_date: the date until when the data from X would be used for
              training. This is useful if you want to use a portion
              of X to train the model. (So, the model wiil be trained
              on X[:end_date index])

    returns: y from start_date to end_date by imputing earlier missing data
    """
    start_date = datetime.strptime(start_date, "%Y-%m-%d").date()
    end_date = datetime.strptime(end_date, "%Y-%m-%d").date()

    if end_date < y.index[0] or end_date < X.index[0]:
        logging.error(
            "training end date is too early, using all of the available lending protocol data for training"
        )
        end_date = y.index[-1]

    if start_date < X.index[0]:
        logging.error(
            "impute start date is too early, using the earliest valid date as start"
        )
        start_date = X.index[0]

    # if impute date is after training start date, we can just return y
    if y.index[0] <= start_date:
        return y

    X_train = X[
        (X.index >= y.index[0]) & (X.index < end_date) & (X.index.isin(y.index))
    ]
    y_train = (
        y[(y.index < end_date) & (y.index.isin(X_train.index))]
        .to_numpy()
        .reshape((-1,))
    )
    X_test = X[(X.index >= start_date) & (X.index < y.index[0])]
    if len(X_train) < 100:
        logging.error("Not enough data for lending protocol. Not imputing data.")
        return y

    model = LinearRegression()
    model.fit(X_train, y_train)
    y_pred = model.predict(X_test)

    # make sure the predicted values are not too far off from mean interest rate
    # replace values 2*std far from mean with mean
    mean, std = y_train.mean(), y_train.std()
    y_pred = np.where(
        (y_pred > mean + 2 * std) | (y_pred < mean - 2 * std), mean, y_pred
    )

    # create a DataFrame of the imputed data with index
    df_y_pred = pd.DataFrame(
        y_pred.reshape((-1, 1)), index=X_test.index, columns=y.columns
    )
    # append the imputed data to y and return it
    return df_y_pred.append(y)


def convert_wide_to_long(df, variable_col, value_col, index_col="timestamp"):
    """
    convert wide format data to long format data
    use original index as id var and all other columns as value vars
    variable_col : name of the variable column in the long format
    value_col    : name of the value column in the long format
    index_col    : name of the index column in the long format
    """
    df = pd.melt(df.reset_index(), id_vars=["index"], value_vars=df.columns)
    df.sort_values(["index", "variable"], inplace=True)
    df.rename(
        columns={"variable": variable_col, "value": value_col, "index": index_col},
        inplace=True,
    )
    return df
