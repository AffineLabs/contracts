// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IMiniChef {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. SUSHI to distribute per block.
        uint256 lastRewardBlock; // Last block number that SUSHI distribution occurs.
        uint256 accSushiPerShare; // Accumulated SUSHI per share, times 1e12. See below.
    }

    function sushi() external view returns (address);
    function poolLength() external view returns (uint256);
    function poolInfo(uint256 pid) external view returns (IMiniChef.PoolInfo memory);
    function userInfo(uint256 pid, address user) external view returns (IMiniChef.UserInfo memory);
    function lpToken(uint256 pid) external view returns (address);
    function totalAllocPoint() external view returns (uint256);
    function deposit(uint256 _pid, uint256 _amount, address _to) external;
    function withdraw(uint256 _pid, uint256 _amount, address _to) external;
}
