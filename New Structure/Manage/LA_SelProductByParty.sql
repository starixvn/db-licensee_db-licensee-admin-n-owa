USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_SelProductByParty] 
	 @PartyID		INT		= 0
	, @excludeTest	BIT		= 0	
AS
/*
Created: 20150312@Florent
Task : Get all product by a party
DB: DB052.bodb_licensee
Revison:

Revisions:
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
		FROM dbo.OAS_ChargeInfo AS c
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
GRANT VIEW DEFINITION ON [dbo].[LA_SelProductByParty] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_SelProductByParty] TO bodbAdminNet