import {CommonVaultTest, ERC20} from "src/test/CommonVault.t.sol";
import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {Vault} from "src/vaults/Vault.sol";

import "forge-std/console.sol";

contract L2VaultV2_IntegrationTest is CommonVaultTest {
    function setUp() public virtual override {
        vm.createSelectFork("polygon", POLYGON_FORK_BLOCK);

        L2Vault impl = new L2Vault();
        vault = Vault(0x829363736a5A9080e05549Db6d1271f070a7e224);

        governance = 0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0;
        vm.prank(governance);
        vault.upgradeTo(address(impl));
        asset = ERC20(vault.asset());
    }

    function _giveAssets(address user, uint256 assets) internal override {
        deal(address(asset), address(user), assets);
    }
}
