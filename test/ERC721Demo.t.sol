// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/ERC720Demo.sol";

contract ERC721DemoTest is Test {
    BaseERC721 public nft;
    BaseERC721Receiver public receiver;

    address public owner = address(0x1000);
    address public user1 = address(0x2001);
    address public user2 = address(0x2002);
    address public user3 = address(0x2003);
    address public operator = address(0x3000);

    string public constant NFT_NAME = "MyNFT";
    string public constant NFT_SYMBOL = "MNFT";
    string public constant BASE_URI = "https://api.example.com/token/";

    function setUp() public {
        vm.prank(owner);
        nft = new BaseERC721(NFT_NAME, NFT_SYMBOL, BASE_URI);
        receiver = new BaseERC721Receiver();
    }

    // ========== 构造函数 & 元数据 ==========

    function test_Constructor() public {
        assertEq(nft.name(), NFT_NAME);
        assertEq(nft.symbol(), NFT_SYMBOL);
    }

    function test_SupportsInterface() public {
        assertTrue(nft.supportsInterface(0x01ffc9a7)); // ERC165
        assertTrue(nft.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(nft.supportsInterface(0x5b5e139f)); // ERC721Metadata
        assertFalse(nft.supportsInterface(0xffffffff)); // Invalid
    }

    // ========== Mint ==========

    function test_Mint() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.balanceOf(user1), 1);
    }

    function test_MintMultiple() public {
        vm.prank(owner);
        nft.mint(user1, 1);
        vm.prank(owner);
        nft.mint(user1, 2);
        vm.prank(owner);
        nft.mint(user2, 3);

        assertEq(nft.balanceOf(user1), 2);
        assertEq(nft.balanceOf(user2), 1);
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user1);
        assertEq(nft.ownerOf(3), user2);
    }

    function test_MintToZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert("ERC721: mint to the zero address");
        nft.mint(address(0), 1);
    }

    function test_MintExistingTokenReverts() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(owner);
        vm.expectRevert("ERC721: token already minted");
        nft.mint(user2, 1);
    }

    // ========== TokenURI ==========

    function test_TokenURI() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        string memory uri = nft.tokenURI(1);
        // 期望 URI 包含 baseURI
        assertTrue(bytes(uri).length > 0);
    }

    function test_TokenURI_NonexistentReverts() public {
        vm.expectRevert("ERC721Metadata: URI query for nonexistent token");
        nft.tokenURI(999);
    }

    // ========== BalanceOf & OwnerOf ==========

    function test_BalanceOf_ZeroAddressReverts() public {
        vm.expectRevert("ERC721: balance query for the zero address");
        nft.balanceOf(address(0));
    }

    function test_OwnerOf_NonexistentReverts() public {
        vm.expectRevert("ERC721: owner query for nonexistent token");
        nft.ownerOf(999);
    }

    function test_BalanceOf_AfterTransfer() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        nft.transferFrom(user1, user2, 1);

        assertEq(nft.balanceOf(user1), 0);
        assertEq(nft.balanceOf(user2), 1);
    }

    // ========== Approve ==========

    function test_Approve() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        nft.approve(user2, 1);

        assertEq(nft.getApproved(1), user2);
    }

    function test_Approve_ToOwnerReverts() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        vm.expectRevert("ERC721: approval to current owner");
        nft.approve(user1, 1);
    }

    function test_Approve_NotOwnerReverts() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user2);
        vm.expectRevert("ERC721: approve caller is not owner nor approved for all");
        nft.approve(user3, 1);
    }

    function test_Approve_OperatorCanApprove() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        nft.setApprovalForAll(operator, true);

        vm.prank(operator);
        nft.approve(user2, 1);

        assertEq(nft.getApproved(1), user2);
    }

    function test_GetApproved_NonexistentReverts() public {
        vm.expectRevert("ERC721: approved query for nonexistent token");
        nft.getApproved(999);
    }

    // ========== SetApprovalForAll ==========

    function test_SetApprovalForAll() public {
        vm.prank(user1);
        nft.setApprovalForAll(operator, true);

        assertTrue(nft.isApprovedForAll(user1, operator));
    }

    function test_SetApprovalForAll_Revoke() public {
        vm.prank(user1);
        nft.setApprovalForAll(operator, true);
        vm.prank(user1);
        nft.setApprovalForAll(operator, false);

        assertFalse(nft.isApprovedForAll(user1, operator));
    }

    function test_SetApprovalForAll_ToCallerReverts() public {
        vm.prank(user1);
        vm.expectRevert("ERC721: approve to caller");
        nft.setApprovalForAll(user1, true);
    }

    // ========== TransferFrom ==========

    function test_TransferFrom() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        nft.transferFrom(user1, user2, 1);

        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.balanceOf(user1), 0);
        assertEq(nft.balanceOf(user2), 1);
        // 转账后授权应被清除
        assertEq(nft.getApproved(1), address(0));
    }

    function test_TransferFrom_ClearsApproval() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        nft.approve(user3, 1);

        vm.prank(user1);
        nft.transferFrom(user1, user2, 1);

        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.getApproved(1), address(0));
    }

    function test_TransferFrom_NotOwnerReverts() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user2);
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        nft.transferFrom(user1, user2, 1);
    }

    function test_TransferFrom_ToZeroAddressReverts() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        vm.expectRevert("ERC721: transfer to the zero address");
        nft.transferFrom(user1, address(0), 1);
    }

    function test_TransferFrom_WrongFromReverts() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        vm.expectRevert("ERC721: transfer from incorrect owner");
        nft.transferFrom(user2, user3, 1);
    }

    function test_TransferFrom_ByApproved() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        nft.approve(user2, 1);

        vm.prank(user2);
        nft.transferFrom(user1, user3, 1);

        assertEq(nft.ownerOf(1), user3);
    }

    function test_TransferFrom_ByOperator() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        nft.setApprovalForAll(operator, true);

        vm.prank(operator);
        nft.transferFrom(user1, user2, 1);

        assertEq(nft.ownerOf(1), user2);
    }

    // ========== SafeTransferFrom ==========

    function test_SafeTransferFrom() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        nft.safeTransferFrom(user1, address(receiver), 1);

        assertEq(nft.ownerOf(1), address(receiver));
    }

    function test_SafeTransferFrom_WithData() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user1);
        nft.safeTransferFrom(user1, address(receiver), 1, "0x1234");

        assertEq(nft.ownerOf(1), address(receiver));
    }

    function test_SafeTransferFrom_NotOwnerReverts() public {
        vm.prank(owner);
        nft.mint(user1, 1);

        vm.prank(user2);
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        nft.safeTransferFrom(user1, user2, 1);
    }

    // ========== 综合场景 ==========

    function test_FullLifecycle() public {
        // 铸造
        vm.prank(owner);
        nft.mint(user1, 1);
        vm.prank(owner);
        nft.mint(user1, 2);
        vm.prank(owner);
        nft.mint(user2, 3);

        assertEq(nft.balanceOf(user1), 2);
        assertEq(nft.balanceOf(user2), 1);

        // 授权
        vm.prank(user1);
        nft.approve(user2, 1);

        // user2 通过授权转走 token 1
        vm.prank(user2);
        nft.transferFrom(user1, user3, 1);
        assertEq(nft.ownerOf(1), user3);

        // 设置操作者
        vm.prank(user1);
        nft.setApprovalForAll(operator, true);

        // 操作者转走 token 2
        vm.prank(operator);
        nft.safeTransferFrom(user1, address(receiver), 2);
        assertEq(nft.ownerOf(2), address(receiver));

        // 最终余额验证
        assertEq(nft.balanceOf(user1), 0);
        assertEq(nft.balanceOf(user2), 1);
        assertEq(nft.balanceOf(user3), 1);
        assertEq(nft.balanceOf(address(receiver)), 1);
    }
}
