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
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]


	 Params:
		+ 0 get all products
		+ <> 0 all product by PayerID
	 Example:
		EXEC dbo.LA_ProductListByPayerSel 0
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @SLTCutoffDate DATE = '2021-10-31'

	SELECT p.ProductId, p.ProductCode AS ProductPrefix , p.ProductName
	FROM dbo.LA_f_GroupProduct('',@SLTCutoffDate,@SLTCutoffDate) p
	WHERE EXISTS (
		SELECT 1
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeId = cs.ChargeId AND cs.SystemId = 2
		WHERE c.ProductId = p.ProductId
			AND c.ToParty IN (1, 9, 11, 98) -- Licensee to House
			AND c.ChargeType NOT IN (2, 3) -- Old Type
			AND (@PayerId = 0 OR c.FromParty = @PayerId)
	)
		AND p.ProductId = p.GroupProductId
	ORDER BY p.ProductId
	
END
GO