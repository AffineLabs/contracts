// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TwoAssetBasket, TestPlus} from "src/test/TwoAssetBasket.t.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {console2} from "forge-std/console2.sol";

contract TwoAssetBasket_UpgradeIntegrationStorageTest is TestPlus {
    TwoAssetBasket vault;
    ERC20 asset;

    function setUp() public {
        vm.createSelectFork("polygon", 51_364_628);

        vault = TwoAssetBasket(0x1F9b1057cd93fb2d07d18810903B791b56acc2E1);
        governance = vault.governance();
        asset = ERC20(vault.asset());
    }

    function _upgrade() internal {
        TwoAssetBasket impl = new TwoAssetBasket();
        vm.prank(governance);
        vault.upgradeTo(address(impl));
    }

    function testStorageValueCheck() public {
        // check storage value from reading public functions
        address vaultAsset = address(vault.asset());
        string memory name = vault.name();
        string memory symbol = vault.symbol();
        uint256 totalSupply = vault.totalSupply();
        address btc = address(vault.btc());
        address weth = address(vault.weth());
        address gov = vault.governance();

        _upgrade();

        assertTrue(vaultAsset == address(vault.asset()));
        assertEq(name, vault.name());
        assertEq(symbol, vault.symbol());
        assertTrue(totalSupply == vault.totalSupply());
        assertTrue(btc == address(vault.btc()));
        assertTrue(weth == address(vault.weth()));
        assertTrue(gov == address(vault.governance()));
    }
}

contract TwoAssetBasketTearDownTest is TestPlus {
    TwoAssetBasket vault;
    ERC20 asset;

    function setUp() public {
        vm.createSelectFork("polygon", 51_364_628);

        vault = TwoAssetBasket(0x1F9b1057cd93fb2d07d18810903B791b56acc2E1);
        governance = vault.governance();
        asset = ERC20(vault.asset());
    }

    function _upgrade() internal {
        TwoAssetBasket impl = new TwoAssetBasket();
        vm.prank(governance);
        vault.upgradeTo(address(impl));
    }

    function testTearDown() public {
        _upgrade();
        vm.prank(governance);
        vault.pause();
        address[452] memory users = [
            0x0FBeABcaFCf817d47E10a7bCFC15ba194dbD4EEF,
            0x7b303Ed0c6B088E0c0D74f6227b11CF928301075,
            0x553222B267bC978ACa3C28493AEf72d924b264BD,
            0xc55ee0528a58e198cb815Dcd0c8Fa5D48585db96,
            0xE8C97650AA7E4525cc45851af5b2f5F81403432A,
            0x5BbEfACCC1A8E1ECb0d470F941668562eEB46FF0,
            0x59CA75D497702251aE552E30E513D146fBED69BC,
            0x01a96DEe51008e20964d7Ee6bA3012cec137Cc39,
            0x5f9908aa2af7653CC50f9d93416B8c96E18b957F,
            0xfAaF5645B877f3aF3D35220b8C4BC2198E68F4bB,
            0x6b17d279dc4f544F7f3B93346827D5B51fa84b0C,
            0xf2DC787F600e1180bea8319A9CDb579F4a7D084e,
            0x11e8C073f377A8dab78B6897616efCbEA19dfd9f,
            0x91a0CaCb38470B50E3117F114762F605C06A1c08,
            0x6D23d81A9054999796e327D07A0Cd3364F1fBfF8,
            0xfb7A5DADe103Cd882587cDB2887eE9c5eAb1cE70,
            0x06C31B6D5a35e26Eff518A4DC0F023d2A8C7Be0c,
            0xF4810d4F5F23D8e3cF9A65d5a588dedefBc71407,
            0xeFD91ecD3bF27e97729bDDC79896F4E33C6020b6,
            0xc90D97f15D30e74146B0eb805FC7Eed6a9E54B73,
            0xa7e999cFFE7E5c43Eb1c20Bac7c42b529F4f0031,
            0xC1a937A725583cA22353929C9C9ecDde3b0c70c2,
            0x61A0659018b581D4217244B71C5AC8c4621Fa830,
            0x42b1D8cB418959AC8A17f60393776e147a506D03,
            0x98d40CDB507f5e9Dfcd60f1471e41d5f2E89EABC,
            0xbCdDe113e0Be48145d119f6ec87a78582CD1398C,
            0x0479760ed93a78f29a57D23B0C3bffF987A15332,
            0x03Edd76C30398a47B61857138D1197Cad32Db02f,
            0x88e137bd3C1d8E94162B48034b221335f7aCe9ff,
            0xeE8513d68899384Fd0d56F1F04314A0604d9eD9B,
            0xB0d37023043099797dfbD2bAefc20f930279dC21,
            0xAC86865Ead332e31B1c2d414BA3991618C64A1F1,
            0xfc694B1E0A40CE491A63546D3675324a32151AC2,
            0xFb9D3EF27b311Cb4EF76c318FA4d3356d63A123C,
            0x590C673a9803748bF412cCEa5FedF71AEDA3EeB5,
            0x41ec28eceb137789032B2B505A57c1dA829934CD,
            0xEE6b71B0b9E8a2e7A30F3f966A41C8b414d5e2cC,
            0x42f6725e27f4500779815217F811DE304f17D353,
            0xb54ce4E053D838412710DA7Aac71A81F65796651,
            0xD838efbA49E0816Fd8C2d3B52C0b4632F030fd8A,
            0x2a68272F9Ed46c0141494b4c7949C3FB40801683,
            0x0abf6C46bf2EEd15DA3509Adb6EBa1a2285d8563,
            0x294505b89F9621FB06E93a47aF70847B2484020b,
            0x4e79f7C7dEED79C53e73c6333BCE526D33c07C8E,
            0xBe71a7993d0BA3C7f3ECE9dC8C108EA9F0699297,
            0x8074B1285c0Fba1F4F9d0ef586c274Bd1e2fa509,
            0xf11Dd9A09036D23aa59c8684F021974F2E42a6FD,
            0xFe7408CaEFF03E70D6Be1A060298f6d425E81Ee5,
            0x1871F42B4BAFeaF5FB95CDC57d32820fF687Fe74,
            0x5AB9125A5a07797432b022E6F9b573f23c34a012,
            0x514EfC11603d5bc5E8fAcD58C46F5aF2b16dc406,
            0x2B5eF7f8D42feB86ba3d4eEC6e325eC314105f29,
            0x3909e2591C958Ef17e61092B891e63F9ba34519F,
            0xF38fFaE62d44bB3742ffA77bc2988df44dA449Bb,
            0x85e830e99e718ab7a5C6F129ee5E3449A81f9Bfd,
            0xbc23B26568cE8ED7c3a0F576512c4a5BD7442eDE,
            0x493BEbFf5aDD3265db2C71a6150802af6AF8802c,
            0x3b1939DaE2C4C97A7B74beDc83c1a0C5673B2b1C,
            0x8d37fFa50aC1EFCC0c1C0c52e6741433F3793565,
            0xCe089C06F40737683143eA7eAeD4f773f1492c44,
            0xB0634731F0Adba7D694a192d1713d5c66Bbad832,
            0x49648311Eb4136b8A1574B883BCD38F9EEd0261f,
            0xe5b75B26e453F7947e606230EbC576abE862cC29,
            0xDE280a28b3a55B976D11bFA5CD6982Efa5169a59,
            0x874f51a45614D249088dE4C853Dc1a5640E4F004,
            0x1a056a2cF4CfdC7ab6f27eed8baEA43886F6AB40,
            0x3cc026C75caF73347371ec4d78Dd82424ef022e2,
            0xf4E02A4B969302D4F4D34c2cabd984647177Bc94,
            0xD118948A587Ed73945506812Ab57b498B696290B,
            0x9E8C3A8c7F7297A9a5Cd9868F00C311157D88dC9,
            0x6E835cd1adE6D2e5EDaeff85c9B778c148451E68,
            0x36DC8895F26ea36D7afc5A8C0C2370C1cF415015,
            0x2Ab4a96CA02862DF402fdD939d48d4De5C626191,
            0x126CB9Ce08aAa9D9920b542d9021A789bE986008,
            0xB7A8969219F2f8108Fb8daC4b30cC944c1cD833b,
            0x6f8b5a36e967362818850140F7296651F3528f35,
            0x2Af8f640c839544044334DaF6d9D124eFC52260b,
            0x24719685EfA96FCd19D31703F5291C3f5a4EeFC7,
            0xA72Ac575Ce5D86876b43b2AC073ecBa2B997db2F,
            0xd714b4B509B9293E7AA25b8caECaB9cCC98CF2CD,
            0xAdc24d435CB051A98ceb5961343792f737035F0E,
            0x7d0B61474564FDedEE5B711B5Bc370D636AB6794,
            0x832A560499829c9717eAaa9Ec238045B5C345267,
            0x3D096a48DD10802B4Ef89c5b7E9D590e6223799E,
            0x1a93FcE8758ac97bf3FA780F85Fe58873985BF03,
            0x2bdf809fde9655F696BC47551653a2613e2Ab4a1,
            0x99437AD0C95435E860dFB2e6995626B3D8809a2E,
            0x0c6037f43ed9B6Ba6499ebCC710AA8b18a07CAf1,
            0x3071aeA7aE75d0ED5830A84F240334b92A91702E,
            0x31012d1270A826a8a40259583a639f5963C778DC,
            0xAf490b4A10b69d59bad2c95e9bd82223e2fb3386,
            0x17272CEb89ECC42C80affbF0EcC5aC90B7BA892B,
            0xAC3405F38cf6F1B7f8Dd72acec69568CC61073e8,
            0x794B170cEE11EAF5603D1ceBE68AD9aE71C8f757,
            0xbf74ce6deAaC1D2646e327fe64a72567C135AdA6,
            0xD4C52B8BB9048dD3BB89BbbF46E41631C5345aaD,
            0xE894FCb9d2343711Eeeca3Cac1039E6D819014f8,
            0xA1eBb566A5278EdeB1471cADc855434886f1c719,
            0x551B8c62F961640278506b408a751CC29A3f4471,
            0x1930b7F236d94E872A0b9DED104Ba092D85A3856,
            0xAD68138D11aA238D59386bA9639D8767636b6e85,
            0x1bb216120E8F939f520C610Bdc3C88aDAc4b06f7,
            0x61A95082f763AD1C6D2891B66ff00De384918B15,
            0xDdAe9f1Ff3bfBc908DcB269F8c1A24aa711F0478,
            0x32A538D59CB0485f742e296F1F0B192823feA671,
            0xF504943CC81c00E784d1477F7B307e90F1a0b2d8,
            0x7E89adc861ca2ea9a054d03bB09056aDE3ccE260,
            0xD4135ABc925a49F82e64953CE4A29dDA5710E196,
            0x5a5d5e19EA0cf1A7Ee89f99BA6143C8682DFEcF3,
            0xa47d7e254565cE23114bbB450AC63ADCDeEF6AA5,
            0xc0f8f0b91e4cACE6d460E2eFc8794e744aBE5E6D,
            0x7D3041492348A4b2D66DD1E7a3B42F93E7dA0004,
            0x990f814fD3262496Da6e15D3e6308e70997c2BBb,
            0x79Bdda65C706CBdA69C0AD4C8da1d3e91724f48D,
            0x2c64a1D5D602E7Fb6d21dA6211DceCc6E17a0649,
            0x1b3fFa3e1A34b3a922f9C3A626F0Ea7ad060ffd6,
            0xB032ADBB1A40CC75203Be46e2ABc42B6237b1624,
            0x7e6eb2123463ca93BD0EF64bbcDde8dB16d77c42,
            0x5ef9f94c5708B01d67985E46FD53f15cF0dA4d2c,
            0xb8e861766202b728efb4Acc1da88926A6560E1cb,
            0xF03336c8c2B040cF026af8774B67127dFF5413A5,
            0xb1646508E4538b2a661Aa0B91fe00388bBF00091,
            0x0aAF37c3EaaA42d417434Fd2ceC555846D46415C,
            0x4BdF57007Be460B851575D833D6b4CA0621A0526,
            0x00Ff21C847F4e6ea9D10422Ab35E1A8614aF6e77,
            0x5209dad745ACC373806dF19aB8117E4b0f541ece,
            0x93e79cC5a42F12ddfe73262FFb1f9535E263b27B,
            0x3eb4912528744D7c5cE5F39B282c8366896253d9,
            0x396F0e55fA33513441d556f84a6eA5c6Fd7d217B,
            0xd5844c4157a8C4F3C113328C5E24d510B4B31BE6,
            0xA9AC152eD9206D61167342B84efCdAa63Da3DE50,
            0x480d8600b0b2D0E2B772Eb68F25d32c7e6D91B7B,
            0xb4dA2aB44E2f418F3d5027E602e409aD9113C6bf,
            0x37b0352665BAe2C0A9Dd46ab909f1129A3FD5528,
            0x6E49A2696E07091E757037d27eB8db7702071ABe,
            0xb0A198Fa79937C594000819312aA57D04a0E477f,
            0x96e1877e833a3297326178625028eab7FD57ff71,
            0xD554D2Bb67bE576913c5B8b0155aE1e2D6C5A496,
            0xC2d70fFE112d9b18c8e093B05C2f785B1CE7cfF2,
            0x5C42bDAE111098BA8E204D9Cf2692D4c861DCA95,
            0x278fdE09f61cB9Af042494Cc4C35d9ee33DFde83,
            0x7d84ad0C2D5797827964ebF7B59e3EaD48b38180,
            0xe01FEDD946d95FD80f3Dbe334d35AA0Cd557Ed0C,
            0xC081f0058bAF3C4788bfd05f0d5eEbf2bF862Dfb,
            0x4450dB99260EC3140B4690F1c6bDd64d5d9644A9,
            0xff88287579C9fA12937c821AfAcFd47EE9e60dcE,
            0xcFB779CEaE93808163df90c18c41aE7566d7faF6,
            0xb122EEC4a3A051d90330ddB6C1b7577cef342313,
            0x66d5d99C831D0222e1E4EFb990B75Dd5cA145068,
            0x43Eac8263d817136f5bf406689718FBE7e4528E5,
            0x443C4E98ED0F741a2ba538d901D2249821E5fbCE,
            0x32e5EeaEAa4e994FAe95b3fCB37843f09426124C,
            0xD0FDeeedA83b2b1823A81d001d5667A340EfF822,
            0xA621cd45FCBB87A558F08e6A576271412e0F2D74,
            0xac12BEbd2f2Ea732d18Ff1132062acF8a15C8E10,
            0x8d200373f44BB836218ae699577dE48Bb38254aa,
            0x34C295Ff1F153bBFB682A311711E2E5A3bc03E6F,
            0x5dc17a8878EB876c70b0f58C659646D8B93EB6FF,
            0x7e11a1A108dfb5c25951d24296b9Bca4a531d0A3,
            0x123487f66340b40b356160D840CEaA4F334E88D5,
            0x1Ec91E85a6B3E3883C1D163afE5e0488860641Cc,
            0x9C04658b5c3Ec349adC32D4dde393c2d040Ee649,
            0x7F7ed74ba8d347640a0a4150751879eFA6a5c8CF,
            0xc76384281f7B7b3e48dB042Fa3c6dd325179DD7A,
            0xbcD162B4a8063d72bF95A1f685D472a45B35d49b,
            0xea67236e4b1dA2aea877dFb714B864714f11fCaf,
            0x7ad9d8711788ef3bCAba5348C5BA3C8d58b58ca8,
            0x9C1d4776C354c2bE97785000c346FB5B40C93a3A,
            0x315CC66e5A95df33f2e453d944349cBFc4bc8E29,
            0x974A4946bCE4dadB4F9d3B5c04121B41AfAF8e40,
            0xdC9C6535B7890C7Afc1885821216169085d97E99,
            0xc0e6955b88dAba4DEaB9DcecFd55533A75b969e9,
            0xDaE8776a87860eefAf9afd6957aEf17fA55654c2,
            0x5Db9D2b63e3026861E1e70c4885763f4372dfEd6,
            0x1d84463985755D518De2076AFd5afD57Fd7f08B4,
            0x17966c2206c5cEE2E2c3B83993B075ECEF7823d0,
            0xab71a525c9a7f0d9C3310654d6b4d59742ea2904,
            0xdA7467A639E6AF379a98CdDF94452e34e336FD62,
            0x983ebEcEE3F50E7313Dd98cC76A9AE687e4EB870,
            0x72A7aeB720Aa7D5b3187757edcF4757fFdb506fc,
            0xbE37d48816921bCb782db8d9237d86A8Ee92F19B,
            0xce764F8944B9c946957595FCb3Bb200d2a67c988,
            0x4983d265507F27Ec7961c9d15E363DBf6F828959,
            0xE3947608e6ecD4EaB132e1867C2E50a47f760F97,
            0xcd27424A27077Bd9d98D3A9fd1F149dD12679419,
            0x55411c49B62852D38Ca21C776D4cA1Af1304E6E1,
            0x223426D9bE67e1217015AD77569948Bc8E333163,
            0x7f6636a5Bf6Dc3d410E61292aC006f1E1cd11136,
            0x57A901Ca3688d505234241d2D6F5a02Ab41c0762,
            0xF3D7459C7F6F75252AAdF594D2Ea74F04B359F82,
            0xB1Eb97BbcC540AfC3E6dE56142780D254961479c,
            0x42DaC65776D0Bf67263650250e3C2317F788308f,
            0x9A9De9D579Af85c5f23a06390078A5799887BD8C,
            0x7e51F4F8d54D6B2c468D0C2A6Fa53ad465c5eEee,
            0xD45791D42C5dA0Df1AE44da5cDB99969595D24Fd,
            0x37f4F18A4fB8743Fdb68dE5afAfc069c76B1d99a,
            0x77884B7aEaCcbf1B8A0C5a33E254391b9B49eA8e,
            0x11315Cce8f009e4CB4234FFEAF2E860b84E5b0f6,
            0x9d28dC122a0f84c0Ee2D855A956c58Ad6bE0479e,
            0x88C9859087493aC3E8bDa3D492DBC89Cf8cbe84B,
            0x13FE83C1A9e49F530786Cce60f27A63B4d8cB229,
            0x2091d60762A994947Dea99f8731aA43F24C33932,
            0xb9eCfeEaf03012b3dB05f7880F90AeF6573327ba,
            0xDC16Db74D4680d31Cb380b985a1013EE435d24Fa,
            0xF39F35f3eD43b2c2525c28ea17b7b6AaCAf1272a,
            0x8E73bABfE963D6b5cb772Cae9F78C912047915dd,
            0x5013e35a20E5B1FFe511B1Ae9299f08627F49f66,
            0xdA62dBD36F934f9A309CBeC2a78f062862bEa747,
            0xdcCDEaB96645535c1491D8966D06640e1BF5B0aC,
            0xFB84493cd2cF0eF811684D3CE28C0C9BDFC9a980,
            0x74f6248d8C5640EC217c4533599c8ECFf834Db3B,
            0xF618A2aFB08971126D21CF60dADE70DD956b1D72,
            0x2Bf08f2E7bf56A5aA496ccC0D71a1D86e4b2910a,
            0x1Ae0016f36aC40Fa88F429dCac423881778f6063,
            0xeF5B0Cf622bAA4c43B16dbc3CEaE473fFAe5164A,
            0xE18c2630Cd512De72dB783E80B2BAD642e1C3FD9,
            0x4b5cA4544E02e186a61f9EF8dd82Ce3632C0cE81,
            0x4eD718cBed23fCb423E5EEa37e22519EBFdE8b56,
            0xFAF60ccC7522580dBD3E9Bd76B2520467cD961c6,
            0x8c67cA8b8146A8bcA2115fA436863fEb33902E6f,
            0x76F2eE77040F5B789D97a9fdBeC9C867168ef977,
            0x9D302f32c78088C4Aa8327f9b321512f85191b00,
            0x48688D720F328e7DA475F04Ff344A737087FcD18,
            0xE8669D44ea965e3E1B03f2FF07087c0d1471e21A,
            0xf03B15D6788A08647133CF0d33414C4a2b28Df6e,
            0x0CDaCfA87D02D055600bbFbcdb6C20520D5ab61a,
            0x1E3f6cdEb3dE774dde708dBb5ec2E0d95aA05b9D,
            0x573c452DAB249cFC6D0E0a0b41488DB50aB40C06,
            0x67B4Ac81cc52D9Fd4F681bE76b7de73a33E59176,
            0x7C1407e99Ea0E998e4094568C31299D86bB0FBcb,
            0x89BfE3C4d18AC6042A9dc74db1CC7eC815296c76,
            0x7c3375B5b253d50e09F35Ed87c8Bd4ae6C085Dc2,
            0xC462E22f430C462BBE2613aD0c9980868ceE292b,
            0xA3683dAFe71b2E05668ae01De7E00BfA1E4366D6,
            0x2bf047D48CdC4654FcfeF5e2DC34b73036Cbe4Ff,
            0xc8685e0Cd1611671c48Cf2d6404dF13e00E0EF2F,
            0xE98b8CBc5fd78722147553d44Edb8F38f41481Db,
            0x450490a9bF5F42868D2f63Ad2Ea88e1FAE2Fa1ce,
            0xcC5801878fbea0706cAE1221EcBF542af665ba44,
            0x429Fbc4c0D3C8bfF46a572b896938AD72df85817,
            0x4F9af2FAE7B3EF1666AF4350aA13E59C0A52bdf0,
            0x85408c03Db0C0394adD4Fd189EDd9dcF26E9B2A1,
            0x8555bAc1879f3f7f8410E14cE2693dB7a394d86c,
            0x117627693f6476579da9Deb954a9a9F6a68320c0,
            0x7129AfC21Bb365d1dC25067f71c888Eb54426934,
            0xF9Ba584f165f941d5FE488495EAF11a23d89dd19,
            0xdf94895ff64012F2832a8bA9Da2fae5E7b68d789,
            0x2abE17d196AF47cb426907bEb10608084E793999,
            0x510945dD51FBB6B5C6031B8B20091Df5Aa5aceD1,
            0xd37886875DE803903c8155db351BFf77cdB53cd4,
            0x84a0c247e3FB8c292f9c5776713B8C88856E76a0,
            0x16071B2D688E5FaA2973d61Ac4F3D9634A7e3eA9,
            0x72A7a13225C196215DA8238Cc2e2D3D9532bA271,
            0xd658145B74d43A27dAc9eD8F108d0C55eC78a2C5,
            0x28A93c4Ec3a6476b511632398B7322C1DE1A5166,
            0xb14fA630FD62a4E4f6b941704e7e8d9f0e0AAf20,
            0x845FDf07F3a10af21A00DC2a56f18cB146cc5c2a,
            0xF8aC524081487a11CA1d96B57e36Ad4c63828691,
            0x6a2B34f43049E74c9aF36F3b17955F732182Ac29,
            0xc7ec06d3C289D6E5070A8Dc10ff6C742E8E8F079,
            0xda2a7293A22bf9E653226CC747e1f5DF6a9bA0d9,
            0x6a4379f763b3e444C8548CCB7B7C061DB3AD7Cb8,
            0xb765006f986CcBed5E7d93373d91377c538E6Ce4,
            0xCBB47EC9AF1dAB922be5E3277CC75F0b58483FF4,
            0xB5C8D6619Bb4879511A02164CB5eaA533FD2fBB0,
            0x916CC151eCe1aBeBCDeD6622319b22f7AEaE13dc,
            0x4310FceD738Ac2D50c199A3c2fF5ea1CA2735b86,
            0x67e174f9C2013b78ecC9D8CB12f3C162c744997b,
            0x62bc28039D7D9595bFEEC5D9C74f51a327E5cbC4,
            0xcCae2a3fD7937Ee4F863494B8edf68B5F3c93E34,
            0xF7530A12b7693dAEDeB707a6F18C12AdAA9bF7FB,
            0x4d80d9539925E76f42746B0f30298e214bBC9Dc3,
            0x46007FA293D4eFBcdC9D8BDDe2f8cd642dd7541b,
            0x409cE813349aDa5DBB189805570eDDEcd9923E58,
            0x463D845Dba8D1680437A936B8bE60ccB4f1EB613,
            0x9077A2ce18849D074A23a3882e9cAe47d0b24cD2,
            0xfB5Bb6B23eF47f805de049349B18484b71582671,
            0x8Bc54D74fDFf1094aAD1fbf4eE83C1b491466403,
            0xf2CFa15591cf73CC3a73A7769938F414946721d7,
            0xd7F98345Abc1f78b1957a711aF174fCd1eA11c53,
            0x1A22a5fBe5b2ECcBFe08beb14d130A5fbBC1f6B8,
            0x5d4Bfaab41336943a40812F0374Dc2479415B4F4,
            0x3E2922D146a247DA9B72CFa65F39045f607143Cf,
            0x8DBf49fB32dA4Afa5a911c5eD4972486D258B813,
            0x08dB9258d1A30E8CEE5EabE5DF3Df64bE2Ea6a2b,
            0x0BEc2Ead96626Ca9c4E1d8E7E179e8e2B457Cc5C,
            0xbbc3Ddc4889d36C881363439F38e24a4BA2933c7,
            0x72eF26434522FF81c486f17703132377543636bf,
            0x086beA508a9A7547bab969B77483f30213524736,
            0xAbe18DD819A8155D6F6364bB7B5FB35A09Fd232E,
            0x1bA74f1280ffaA6180F9608cd7D6A48De766214a,
            0x8DC276193ff29D12fdceDe0D5628734914dEe1ce,
            0xb22Dc520Dc4C9d3Ac70B895aA52EfcD40d17571D,
            0xb597BE3e427805fD0FedEFFe1aBf554D16b54006,
            0x24588BeAf3A248a2C3922AE091Bf198aeAE05b46,
            0x35343C832a396C6A256915D41F9c4E48Ffc07786,
            0x284d5149e9320A0f8FbF6546636A2dc5215EFcf6,
            0x76561CE9f1B077a9FefE03b154abE1A9Db2A51ca,
            0x6Af1c53a7c57269a7E0D35871147488F673CF419,
            0xeCA7c7A8C4b34b469A12DB796Ad7f470D7EF21fa,
            0x7F6C17DA05215D9f9Eb8CddA26a06c2dAF7ab68d,
            0x61c41521c9eea8aABB1F0f727B3Eaff03F358634,
            0x67A82Fac392a3c1b6cbBA7E4b794b9722E8f6C1d,
            0xc936cD929b972D3E145254de589b8e00AF0347C0,
            0xbd82b0a3Bd2BD9eC7CF8B3cA4b2B1B0a21a6153B,
            0xb8917988fbD3d934113F324F566e5f5b1f2a3748,
            0x398B39C510D74D152665fcadD4E847cCfC89cE90,
            0xE9D306eA487F24FcCd8c8ea60c9b2E85FCa2Af48,
            0x57e14dfd0773268D025908Cb2668f4Dc8492696c,
            0x12d737459242B4a80EAc41e1B1dd50b0E4b38878,
            0xB300A1D1986aE26FcC69B7E9B28bDc3f45220673,
            0x8e70DdAd88fd98694a6A2EA9EcA61aa966022C9D,
            0xB284ab1d15004712c81331B41F091175F0E32c54,
            0x648D99b45aD39e131Cb4a714740fAD3e2CA197e6,
            0xE1ED7020e3b59F0768A3dfC52509052190D932BF,
            0x44F82a6eb86FE3686B4163953e956582BF01584a,
            0x1c8aB596A78a03Cde70BE63cA3a8FB3EE06B5275,
            0xfeB6578e9468D466E71C888921fc562d578Cdbb6,
            0x4000e4B0e0297b171440A81B72DDa6e4657219A9,
            0x592ca28529B1F9daF326Dca8Bb919eb5bfED02b6,
            0xE159e05540936Aa90311edD652123a91437B765F,
            0x133c563166c76050c0FA3Ecf6e71D96E21672bFD,
            0x0EB18BB89A915cb8e696A56564af2bD0A6724B06,
            0xB65562eFB809f8f58A9c7f8A34C222E074db81d2,
            0x1eFf7C00085187EDf62099200e867E8D840753e8,
            0xF2f9D450f8052a8d1a30AAd020Dabd36CfEf5a5e,
            0xfdf3B3B1cfE5f4967DabA1719693d589Ba790c1c,
            0xe1e8FF3c683767c3B8cA04138EbE962fcC1869aE,
            0xEE73C386C5Edd7aB40a574A2191105253f1ff3e2,
            0x4220e08512316857aac0DfD28A043643e34d0d43,
            0x3fFcD5D160e866Bc181077B111488903D6c11D82,
            0x398226061a00633c7AFe2AEc8d04A4B4dde74Fe5,
            0xffF6dcF84B70AB308d1a2485AC31D51aa45dAbDc,
            0x923f0DcD966CC3Ce5D0Ae63c93096012C9bE96F5,
            0x927495bC460a73035B357D335691BA61ECDFbE9e,
            0xb19EA4b8C54dFE2c35a84e7414D753D22fDaa1E2,
            0xC047Eb7030147E467fFbDC3E2292B77B4d378cf4,
            0x50eB24A647073E24b7FA5106AEC73e73e8dc18C0,
            0x53f792e5442E7454BFc2c01Ac8A62976B4d35EbD,
            0xf44842057446A0C74F16616a8f3FC2C0bCCCeF8B,
            0x47997B3055D1a51e921007a8C8cD07bf1bf0309A,
            0xee1b9280C711b3C8Feba7Fca58f00904cB846806,
            0x25F0Fc45941629De55463CD138d83b56a6f22D82,
            0x327F15e70207A2991840AD31346B273fEC922639,
            0x37B971519f66a46F996411944EBd920B6a74Ce21,
            0xb52c63e78Dfc168E840d47E8A2eFCA4Ba414FB2D,
            0x91A7A67cf1668d8AB9123bf19efEA2d1d6b72F1e,
            0xbd2A9129ee4861AC8E04d559f04De0AADc430276,
            0xAEe8a1A5Ea577A00f8742c50Ce56Dad270D2C31a,
            0xd49985A4b41c7561399e2184722D51036B89C77b,
            0x23DcE7E64d8203024Ea217d5d7C6002974569DeF,
            0xE3B1214135Ef783C587763050b9DF3e3eCBc4708,
            0x4b07008E7e61a021418f08a010A8392607C3Aa1b,
            0xc86f529E6123A1C9c7933aA90c385E3cd2C44a10,
            0xECE54706571Dee077b5c7FD7C26FB8bC0A2ade21,
            0x5a3Aff4cd7c2050c7a43A9131F9cf632597594bC,
            0xf9Feb5F64d0525259B4CFcf4a996EB76cbd23a7d,
            0x7416D07b771e1D3F6ebb7A72c91a0B34f416406E,
            0xB40BEe5F8d3a25fE19631492CE3Bd54D28556F05,
            0xc8c9410F0798335371607f3f7714985e42F81e43,
            0xfc0a4C2A44b2122936B8480e168f4e6cC5957E7C,
            0x9Dd4a7f00f6c5aDD1AeE3B53Be0CD8f8cdB2673E,
            0x64d009c4C50f01011e97edDBE1Dc95A7E4858dd6,
            0xC18b64A3c31E5519c58C588811F7e629042FcF93,
            0x2cFd1cc53e7e933ac9Ba250e15EbcA2109b71Be4,
            0xfa7b713D7EcbFa17679B49A86c026783E6876cEE,
            0x0f960870C16dA49C9514e767aBF57405FEa2aE56,
            0x53e817A8435cF753d45C8faff3402C565823a269,
            0x8B668f856fFd11aEC0f135d32612605929ED5c3c,
            0xA96d6F6671385f57c6aC28BE35421A9475c85FE1,
            0x13d22A09647E9fE6EF411350196A4f6f9C054d1f,
            0xaA3057e314C2F8Cdf77b651E2F91cB6B791d0Eca,
            0xbd20Ec66B29896547233684B61614252526e3ECe,
            0xba64155D6284A18dE663a38550fB50c656695ded,
            0x6C8D2d6E3f8941142aBfA9Acc42108B2721316D0,
            0x6c1bC85FaA38c392041731e29a3C9dEa7b3CEddA,
            0x44ED39A1840F90C633eE7f8C8fbDe5894c2C8935,
            0x6187f9817960bbDd1ac4DCC58058683229491d74,
            0x39067000aFFe427e3296DA67dB3Fb6038CA0E8dB,
            0xD2bcd090f62d91a76ad5Ba99eda5997b186D29bE,
            0x8e56B898E588Ec11E85542E52e9D624405052C54,
            0x55a3e41588ca78fb31edf773E957EAfbB573dBd2,
            0x9ffF10ba88b9FB7773317C028BBEAE58e8f00584,
            0x16fE76BAc8dbED421FD81fD47D146E053c37D2d0,
            0x50C635fd070cCfE63d2530a65B3Db94c86a78E56,
            0x651bbF2a9E2400358dE60F16A4eB613C9E96e4Fb,
            0xADc48F9eEd3C0E9af74269b0a0cc9FF5BA03673C,
            0x5C3c191641dA4E50C90c2F9e40497113fC126881,
            0x6c784456b5E58251ac0931C9c639d6F8a688d0d9,
            0x83995DD273Bef3C0D3F554b39156F1504406e2F6,
            0xed429E553F4dF3e0F5c22FBCb229b9c11B6056C8,
            0xabdE44e58fd9a4B0767BbF11F7a6c29A86B717Aa,
            0x38Ba563815d41AE8a05c468DF4BAEBe897b655f1,
            0x73ADdB4b3e70ABD0D60A13a30C829dC0e6271733,
            0x1ddf31F4fEA6Fe3FF07A4bE06c3E74F5d027C1de,
            0xF1351fE89F4F9fFF7a6cd5579f63036D751F4852,
            0x48cddC4602Ad1B30C25484F345e9288DeF388bDF,
            0xfA19D483C03a48297c74D236D4B1234Ca9cBFc0e,
            0xdFA8D71772915Bc811efaC8d1473D7E93c1Af3eA,
            0xa1EEF485518f266420e8B987a89A1914373ceB31,
            0x6C90A3F82a40e111680a2B544FE827138aa98798,
            0x2fed8051C128d5Bf4a9a53ac0Ad2cd0D6C14c7Ed,
            0xe9542f1215997DB32D9eaD67F5847BbDC2200f4D,
            0x502Db486feAf0a05E096710c81B6c2d2232751a6,
            0xc7ACB9Fa9d8E51fad0A90D203EC11138c9A83803,
            0xCf2DA80c8D442352fC6D778FC0685447C6995059,
            0xF7BB3867DbEf88D261c5644E01f8Ec510E00758B,
            0x09DF76E8A0564A529f9c534D9b9EB08439e1A5b9,
            0x4F60f5148283c0b05cF6D2a16676E3cAbc36e62c,
            0xdD4A2A75797e9dfE38f6BC9953c4019f7544353C,
            0xFd399A7F9dEC1B0c91961783Dc5fa7fA607D81A2,
            0x848DECc8a1C16644ED64C726a56855ec25894D41,
            0x27F559B7C2f834bCff1A0101B81c22F1142F6838,
            0x7415a096eC3D3fC08bCDFfa632DcbADb840a2286,
            0x86a35132D85EEF41c5Cd7B0E5E164723BA0743F4,
            0xad9A33E65E16bd280505ac362B5476608F0Bc96c,
            0x4e16Fac71F3162cdE3E9304a10a1316F6560fe6e,
            0x232005DD9073A96f2B468591F07d43DD68FA93bd,
            0x26aE728b3363F4Ce2d4B2A3ca912EC3B05933758,
            0x652BEE6c36c34542A87E2cF03a4F224523708e10,
            0xa22b1be754600c2A28746f73a2C5d5A91D33Bf44,
            0xcf215696380E2F455745C398193D95b6b12C523C,
            0xd4E4fEd90aAfCF7EaAF5510F1fE6C2a5B8a48ecb,
            0x098eB3a32C7A7Be63E3cbE8a4Fa620240eE5544f,
            0x6f8b3E110995DAf3c3B48b10E106a7860F3EcacA,
            0x9339510D5D1ad1e10DE9450dbB2e88F032C73FBF,
            0xE208D0acb1008125A3A1d57Cb2C6f27FccBaaFeA,
            0x99cC354E2E3cc597526448D47E70F02AeC5bE0A4,
            0x9BdC5aaE710E4596c0ACe71e58Fb7D31d2b23220,
            0x2A1C4a588E6888648CA62Eca1fadE867dEFF81C0,
            0x9Cc2EB8801f102Df5a28a56a3701e3D5DBF22A7c,
            0x13eE1Ca86B735940d0F4AC6b78972d65c06b010E,
            0x60749075261835035269d038915A544089B41bEC,
            0xD9151b80ea0ac35956e0D7362082A33D9553BFCF,
            0xf0C54Aa3236B4F2d44a30EB84efC42DEc149f60F,
            0x777251e12b7ED019D535CCa313443BC5cb0d2661,
            0x979ad477F779E68f7C655086622cc8935861e698,
            0x245A669f23e47b3fCB81E0D319B287277911c475,
            0xcb86C7D82860C276a8a6Df73Cf8dAD5f1Fa95db4,
            0x92640c67E792a407761CF15A3ec8Ea8471def107,
            0xa2A90A8B2e4EcC719A8a4E885A4b0a64052f8634,
            0xE49be034C028CA4111f5df9c4CAFD975bb2918eC,
            0x2C4725cfE2D84157c95A18472A5792107bC9C57F,
            0xf4e4e72fbAda327Bd2316f6509dD2E38a746993b,
            0x254282d7D408494E066caadAA292B217d3B6507b,
            0x89818ba16dA39Ae473Bc262B3AAED07D2710786A,
            0x1DC6Ee73f8a3257d94DcE3187c552C924Ed3d106,
            0x3Ed6dAE6cC1422e8759bfd2B4f4A253B5b6c6d84,
            0xa405A251aaeb1f2D01875675e84F66d2d3DA37a2,
            0x0F97675747C262C06Bac1AA26810C2D642f3f2E0,
            0xB674DA9b36981FF91bB1b89d51F8d7741D53d2aE,
            0x60b771E420f62e2c28737aEaEc7d1E547b64C450
        ];

        bytes memory data;

        uint256[] memory oldAssets = new uint256[](users.length);
        uint256[] memory shouldReceive = new uint256[](users.length);

        uint256 price = vault.detailedPrice().num;
        uint256 priceDecimals = vault.detailedPrice().decimals;

        uint256 count = 0;

        for (uint256 i = 0; i < users.length; i++) {
            oldAssets[i] = asset.balanceOf(users[i]);
            shouldReceive[i] = vault.balanceOf(users[i]) * price * (10 ** asset.decimals());
            shouldReceive[i] /= ((10 ** vault.decimals()) * (10 ** priceDecimals));

            if (shouldReceive[i] > 1e6) {
                data = bytes.concat(data, abi.encodePacked(users[i]));
                count++;
            }
        }
        vm.prank(governance);
        vault.tearDown(data);

        console2.log("vault tvl %s %s %s", vault.detailedTVL().num, vault.detailedTVL().decimals, count);

        for (uint256 i = 0; i < users.length; i++) {
            if (shouldReceive[i] > 1e6) {
                assertApproxEqRel(shouldReceive[i], asset.balanceOf(users[i]) - oldAssets[i], 0.1e18);
                assertTrue(vault.balanceOf(users[i]) == 0);
            }
        }
    }
}
