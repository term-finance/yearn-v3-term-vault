// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "./Roles.sol";
import "./IAvatar.sol";
import "forge-std/console2.sol";

interface ISafe {
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
    function enableModule(address module) external;
    function swapOwner(
        address prevOwner,
        address oldOwner,
        address newOwner
    ) external;
}

interface IDelay {
    function setUp(bytes memory initParams) external;
    function transferOwnership(address newOwner) external;
    function setTxNonce(uint256 _nonce) external;
}

interface ISafeProxyFactory {
    function createProxyWithNonce(
        address _singleton,
        bytes memory initializer,
        uint256 saltNonce
    ) external returns (address);
}

interface IModuleProxyFactory {
    function deployModule(
        address masterCopy,
        bytes memory initializer,
        uint256 saltNonce
    ) external returns (address proxy);
}

interface ISafeL2 {
    function setupToL2(address l2Singleton) external;
}

interface IDAOFactory {
    /// @notice The container for the DAO settings to be set during the DAO initialization.
    /// @param trustedForwarder The address of the trusted forwarder required for meta transactions.
    /// @param daoURI The DAO uri used with [EIP-4824](https://eips.ethereum.org/EIPS/eip-4824).
    /// @param subdomain The ENS subdomain to be registered for the DAO contract.
    /// @param metadata The metadata of the DAO.
    struct DAOSettings {
        address trustedForwarder;
        string daoURI;
        string subdomain;
        bytes metadata;
    }

    struct Tag {
        uint8 release;
        uint16 build;
    }

    struct PluginSetupRef {
        Tag versionTag;
        address pluginSetupRepo;
    }

    /// @notice The container with the information required to install a plugin on the DAO.
    /// @param pluginSetupRef The `PluginSetupRepo` address of the plugin and the version tag.
    /// @param data The bytes-encoded data containing the input parameters for the installation as specified in the plugin's build metadata JSON file.
    struct PluginSettings {
        PluginSetupRef pluginSetupRef;
        bytes data;
    }

    function createDao(
        DAOSettings calldata _daoSettings,
        PluginSettings[] calldata _pluginSettings
    ) external returns (address createdDao);
}

contract Deployments {
    address public constant SAFE_PROXY_FACTORY =
        0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address public constant SAFE_IMPL =
        0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address public constant SAFE_L2 =
        0xBD89A1CE4DDe368FFAB0eC35506eEcE0b1fFdc54;
    address public constant SAFE_L2_SINGLETON =
        0x29fcB43b46531BcA003ddC8FCB67FFE91900C762;
    address public constant SAFE_PAYMENT_RECEIVER =
        0x5afe7A11E7000000000000000000000000000000;
    address public constant COMPAT_FALLBACK =
        0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;
    address public constant MODULE_PROXY_FACTORY =
        0x000000000000aDdB49795b0f9bA5BC298cDda236;
    address public constant DELAY_MODULE_IMPL =
        0xd54895B1121A2eE3f37b502F507631FA1331BED6;
    address public constant DAO_FACTORY =
        0x7a62da7B56fB3bfCdF70E900787010Bc4c9Ca42e;
    address public constant PLUGIN_SETUP_REPO =
        0x424F4cA6FA9c24C03f2396DF0E96057eD11CF7dF;
    address public constant DEAD_OWNER = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant CHAIN_ID = 11155111;
}

contract GnosisDeployer is Deployments {
    // bytes4(keccak256("isValidSignature(bytes,bytes)")
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x20c13b0b;
    address internal constant SENTINEL_OWNERS = address(0x1);

    constructor() {
        /*uint chainId;
        assembly {
            chainId := chainid()
        }
        require(chainId == CHAIN_ID); */
    }

    function deploySafe(
        address proposer,
        address safeOwner,
        uint256 saltNonce
    ) external {
        // Create proposer safe
        address[] memory owners = new address[](1);
        // using address(this) for enableModule, will transfer to proposer later
        owners[0] = address(this);
        address proposerSafe = ISafeProxyFactory(SAFE_PROXY_FACTORY)
            .createProxyWithNonce(
                SAFE_IMPL,
                abi.encodeWithSelector(
                    ISafe.setup.selector,
                    owners,
                    1,
                    SAFE_L2,
                    abi.encodeWithSelector(
                        ISafeL2.setupToL2.selector,
                        SAFE_L2_SINGLETON
                    ),
                    COMPAT_FALLBACK,
                    address(0),
                    0,
                    SAFE_PAYMENT_RECEIVER
                ),
                saltNonce++
            );

        // Create ownerless safe
        owners[0] = address(this);
        // using address(this) for enableModule, will transfer to safeOwner later
        address ownerlessSafe = ISafeProxyFactory(SAFE_PROXY_FACTORY)
            .createProxyWithNonce(
                SAFE_IMPL,
                abi.encodeWithSelector(
                    ISafe.setup.selector,
                    owners,
                    1,
                    SAFE_L2,
                    abi.encodeWithSelector(
                        ISafeL2.setupToL2.selector,
                        SAFE_L2_SINGLETON
                    ),
                    COMPAT_FALLBACK,
                    address(0),
                    0,
                    SAFE_PAYMENT_RECEIVER
                ),
                saltNonce++
            );

        // Create custom Roles module (owner = ownerlessSafe)
        Roles roles = new Roles(ownerlessSafe, ownerlessSafe, ownerlessSafe);

        // Enable Roles module
        _enableModule(ownerlessSafe, address(roles));

        // Deploy Delay module (owner = ownerlessSafe)
        address delayModule = _deployDelayModule(ownerlessSafe, saltNonce++);

        // Enable Delay module on Ownerless Safe
        _enableModule(ownerlessSafe, delayModule);

        // Enable Delay module on Proposer Safe
        _enableModule(proposerSafe, delayModule);

        // Call transferOwnership on DELAY MODIFIER from OWNERLESS SAFE to ROLE MODIFIER
        _callModuleFunc(
            ownerlessSafe,
            delayModule,
            abi.encodeWithSelector(
                IDelay.transferOwnership.selector,
                address(roles)
            )
        );

        // Call ScopeAllowFunction on ROLE MODIFIER
        _callModuleFunc(
            ownerlessSafe,
            address(roles),
            abi.encodeWithSelector(
                Roles.scopeAllowFunction.selector,
                1,
                delayModule,
                IDelay.setTxNonce.selector,
                ExecutionOptions.None
            )
        );

        // Create Governor/DAO
        IDAOFactory.PluginSettings[]
            memory pluginSettings = new IDAOFactory.PluginSettings[](1);

        pluginSettings[0].pluginSetupRef.versionTag.release = 1;
        pluginSettings[0].pluginSetupRef.versionTag.build = 2;
        pluginSettings[0].pluginSetupRef.pluginSetupRepo = PLUGIN_SETUP_REPO;
        pluginSettings[0].data = hex"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000e100000000000000000000000000000000000000000000000000000000005f5e10000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000336dcfd08e31e728481a065e57708e176bcc6227000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000018476f7665726e616e6365206d6f636b55534443546573743300000000000000000000000000000000000000000000000000000000000000000000000000000008676d7375646374330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        address dao = IDAOFactory(DAO_FACTORY).createDao(
            IDAOFactory.DAOSettings({
                trustedForwarder: address(0),
                daoURI: "",
                subdomain: "",
                metadata: hex"697066733a2f2f6261666b7265696871346e3233716f767a686961767476346a6a6b6664707a666463366a3368666b63726f6568666d696366336e75326132346d34"
            }),
            pluginSettings
        );

        // call enableModule on ROLE MODIFIER (allow governor)
        _callModuleFunc(
            ownerlessSafe, 
            address(roles),
            abi.encodeWithSelector(
                ISafe.enableModule.selector, 
                dao
            )
        );

        // call assignRoles on ROLE MODIFIER to allow governor role 1
        uint16[] memory daoRoles = new uint16[](1);
        bool[] memory roleMembers = new bool[](1);

        daoRoles[0] = 1;
        roleMembers[0] = true;
        _callModuleFunc(
            ownerlessSafe,
            address(roles),
            abi.encodeWithSelector(
                Roles.assignRoles.selector,
                dao,
                daoRoles,
                roleMembers
            )
        );

        // call allowTarget on ROLE MODIFIER allow role 1 to delay mod
        _callModuleFunc(
            ownerlessSafe,
            address(roles),
            abi.encodeWithSelector(
                Roles.allowTarget.selector, 
                1,
                dao,
                ExecutionOptions.None
            )
        );

        // transfer ownership from address(this) to proposer
        _swapOwner(proposerSafe, proposer);

        // transfer ownership from address(this) to DEAD_OWNER (ownerless)
        _swapOwner(ownerlessSafe, DEAD_OWNER);
    }

    function _swapOwner(address safe, address newOwner) private {
        ISafe(safe).execTransaction(
            safe,
            0,
            abi.encodeWithSelector(
                ISafe.swapOwner.selector,
                SENTINEL_OWNERS,    // prevOwner
                address(this),      // oldOwner
                newOwner
            ),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            _getSignature()
        );        
    }

    function _deployDelayModule(
        address delayOwner,
        uint256 saltNonce
    ) private returns (address) {
        return
            IModuleProxyFactory(MODULE_PROXY_FACTORY).deployModule(
                DELAY_MODULE_IMPL,
                abi.encodeWithSelector(
                    IDelay.setUp.selector,
                    abi.encode(delayOwner, delayOwner, delayOwner, 3600, 86400)
                ),
                saltNonce
            );
    }

    function _callModuleFunc(
        address safe,
        address module,
        bytes memory data
    ) private {
        ISafe(safe).execTransaction(
            module,
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            _getSignature()
        );
    }

    function _enableModule(address safe, address module) private {
        ISafe(safe).execTransaction(
            safe,
            0,
            abi.encodeWithSelector(
                ISafe.enableModule.selector,
                address(module)
            ),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            _getSignature()
        );
    }

    function _getSignature() private view returns (bytes memory) {
        return
            abi.encodePacked(
                bytes32(uint256(uint160(address(this)))),
                bytes32(uint256(65)),
                uint8(0),
                uint256(32),
                bytes32(uint256(uint160(address(msg.sender))))
            );
    }

    /*    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) public view returns (bytes4 magicValue) {
   //     console2.logBytes(_signature);
        return MAGICVALUE;
    } */

    function isValidSignature(
        bytes memory _data,
        bytes memory _signature
    ) public view returns (bytes4 magicValue) {
        //     console2.logBytes(_signature);
        return EIP1271_MAGIC_VALUE;
    }
}
