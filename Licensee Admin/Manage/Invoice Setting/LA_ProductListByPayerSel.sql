/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ProductListByPayerSel]
	 @PayerId	INT	= 0	
AS
/*  
	 Created: 20150413@Florent
	 Task : get List Products by Payerid or get all
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20150413@Florent: Initialize SP
		- 20210812@Percy: Exclude BitCoin from Product drop-down list [RedmineID: #159691]

	 Params:
		+ 0 get all products
		+ <> 0 all product by PayerID
	 Example:
		EXEC dbo.LA_ProductListByPayerSel 0
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT p.ProductId, p.ProductPrefix, p.ProductName
	FROM dbo.LA_f_Products3rd('') p
		LEFT JOIN dbo.LA_f_GroupProduct() g ON p.ProductId = g.ProductId AND g.ProductId <> g.GroupProductId
	WHERE EXISTS (
		SELECT 1
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeId = cs.ChargeId AND cs.SystemId = 2
		WHERE c.ProductId = p.ProductId
			AND c.ToParty IN (1, 9, 11, 98) -- Licensee to House
			AND c.ChargeType NOT IN (2, 3) -- Old Type
			AND (@PayerId = 0 OR c.FromParty = @PayerId)
	)
		AND g.ProductId IS NULL
	ORDER BY p.ProductId
END
GO