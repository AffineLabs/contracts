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

    # training starts on the first day of available data for y
    X_train_start_idx = (y.index[0] - X.index[0]).days
    # training ends on end_day
    X_train_end_idx = (end_date - X.index[0]).days
    y_train_end_idx = (end_date - y.index[0]).days
    # data impuatation starts on start_day
    impute_start_idx = (start_date - X.index[0]).days

    if (
        X_train_start_idx >= X_train_end_idx
        or X_train_end_idx < 0
        or y_train_end_idx < 0
    ):
        logging.error(
            "training end date is too early, using all of the available lending protocol data for training"
        )
        X_train_end_idx = len(X) - 1
        y_train_end_idx = len(y) - 1

    if impute_start_idx < 0:
        logging.error(
            "start date is too early, using all of the available lending protocol data for training"
        )
        impute_start_idx = 0

    X_train = X[X_train_start_idx:X_train_end_idx]
    X_test = X[impute_start_idx:X_train_start_idx]
    y_train = y[:y_train_end_idx].to_numpy().reshape((y_train_end_idx,))

    if impute_start_idx < X_train_start_idx:
        # impute date is before the training start date,
        # so need to use the model to generate y
        model = LinearRegression()
        model.fit(X_train, y_train)
        y_pred = model.predict(X_test)
        y_pred_index = X.index[impute_start_idx:X_train_start_idx]
        # create a DataFrame of the imputed data with index
        df_y_pred = pd.DataFrame(
            y_pred.reshape((-1, 1)), index=y_pred_index, columns=y.columns
        )
        # append the imputed data to y and return it
        return df_y_pred.append(y)
    else:
        # impute date is after training start date, so we can just
        # return y
        return y


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
