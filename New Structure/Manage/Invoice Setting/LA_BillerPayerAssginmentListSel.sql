USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_BillerPayerAssginmentListSel]
	 @BillerId	INT	= 0	
AS
/*  
	 Created: 20150408@Florent
	 Task : Get Inoive setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
		+ 0 get all biller
		+ <> 0 specify a biller 
	 Example:
		EXEC dbo.[LA_BillerPayerAssginmentListSel] 0
*/
SET NOCOUNT ON
BEGIN
	CREATE TABLE #ProductsID (ProductID TINYINT, ProductPrefix VARCHAR(10), ProductName VARCHAR(50))
	BEGIN  
		INSERT INTO #ProductsID(ProductID, ProductPrefix, ProductName)  
		SELECT ProductID, ProductPrefix, ProductName 
		FROM dbo.Product3rd WITH (NOLOCK)
		UNION
		SELECT 0, 'SB', 'Sportbooks'			
	END
	
	SELECT i.ToPartyID, b.BillerName, i.FromPartyId, i.InvTypeId,i.InvTempId, COUNT(i.ProductId) AS NumbOfProducts	
		,STUFF((
				SELECT ', ' + CAST(pp.ProductName AS VARCHAR)
				FROM dbo.LA_InvoiceSetting ii WITH (NOLOCK)
					LEFT JOIN #ProductsID pp ON ii.ProductId = pp.Productid
				WHERE i.FromPartyId = ii.FromPartyId AND i.ToPartyID = ii.ToPartyID
				FOR XML PATH (''))
			  , 1, 2, '') AS ProductList
	FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyID = b.PartyID		
		INNER JOIN dbo.LA_InvoiceSetting i WITH (NOLOCK) ON i.ToPartyId = p.PartyID
	WHERE p.PartyType = 4 
		AND (@BillerId = 0 OR p.PartyID = @BillerId)
	GROUP BY i.ToPartyID, b.BillerName, i.FromPartyId, i.InvTypeId, i.InvTempId

	DROP TABLE #ProductsID
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_BillerPayerAssginmentListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_BillerPayerAssginmentListSel] TO bodbAdminNet 