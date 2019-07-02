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

Param's Explanation:
*/
SET NOCOUNT ON

BEGIN
	--DECLARE @temp AS TABLE (ProductID INT)

	BEGIN
		--INSERT INTO @temp(ProductID)
		SELECT CASE WHEN c.ProductID = 0 THEN 'SB'
					 ELSE pr.ProductPrefix
				END AS ProductCode 
			, CASE WHEN c.ProductID = 0 THEN 'Sportsbook'
					 ELSE pr.ProductName
				END AS ProductName
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK) 
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeID = cs.ChargeID AND cs.SystemID = 2
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON c.FromParty = p.PartyID
			LEFT JOIN dbo.Product3rd pr WITH (NOLOCK) ON c.ProductID = pr.Productid	
		WHERE (@PartyID = 0 OR p.PartyID = @PartyID)
		GROUP BY pr.Productid
			, CASE WHEN c.ProductID = 0 THEN 'SB'
					 ELSE pr.ProductPrefix
				END 
			, CASE WHEN c.ProductID = 0 THEN 'Sportsbook'
					 ELSE pr.ProductName
				END
		ORDER BY pr.Productid
	END
END
GO