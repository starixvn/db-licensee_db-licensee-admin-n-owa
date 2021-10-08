/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_SelProductByParty] 
	 @PartyID		INT		= 0
	, @excludeTest	BIT		= 0	
AS
/*
Created: 20150312@Florent
Task : Get all product by a party
DB: DBCUST.bodb_licensee

Revisions:
	- 20150312@Florent: Initialize SP
	- 20210812@Percy: Exclude BitCoin from Product drop-down list [RedmineID: #159691]

Param's Explanation:
*/
SET NOCOUNT ON

BEGIN
	SELECT p.ProductPrefix AS ProductCode, p.ProductName
	FROM dbo.LA_f_Products3rd('') p
		LEFT JOIN dbo.LA_f_GroupProduct() g ON p.ProductId = g.ProductId AND g.ProductId <> g.GroupProductId
	WHERE EXISTS (
		SELECT 1
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeId = cs.ChargeId AND cs.SystemId = 2
		WHERE c.ProductId = p.ProductId
			AND c.ToParty IN (1, 9, 11, 98) -- Licensee to House
			AND c.ChargeType NOT IN (2, 3) -- Old Type
			AND (@PartyId = 0 OR c.FromParty = @PartyId)
	)
		AND g.ProductId IS NULL
	ORDER BY p.ProductId
END
GO