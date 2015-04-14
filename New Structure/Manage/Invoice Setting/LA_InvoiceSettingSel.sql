USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_InvoiceSettingSel]
	 @BillerId	INT	= 0		 
	 , @PayerId	INT = 0
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
		EXEC dbo.LA_InvoiceSettingSel 123, 14
*/
SET NOCOUNT ON
BEGIN
	DECLARE @Products AS TABLE (ProductID TINYINT, ProductPrefix VARCHAR(10), ProductName VARCHAR(50))
	INSERT INTO @Products(ProductID, ProductPrefix, ProductName)
	SELECT ProductID, ProductPrefix, ProductName
	FROM dbo.[LA_f_Products3rd]('') -- get all
	
	SELECT i.ToPartyID			AS BillerId
		, b.BillerName			AS BillerName
		, i.FromPartyId			AS PayerId
		, p1.PartyName			AS PayerName
		, i.InvTypeId			AS InvTypeId
		, tp.InvTypeName		AS InvTypeName
		, i.InvTempId			AS InvTempId
		, temp.InvTemplateName	AS InvTemplateName
		, COUNT(i.ProductId)	AS NumbOfProducts
		,STUFF((
				SELECT ', ' + CAST(pp.ProductName AS VARCHAR)
				FROM dbo.LA_InvoiceSetting ii WITH (NOLOCK)
					LEFT JOIN @Products pp ON ii.ProductId = pp.Productid
				WHERE i.FromPartyId = ii.FromPartyId AND i.ToPartyID = ii.ToPartyID
				FOR XML PATH (''))
			  , 1, 2, '') AS ProductList
	FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyID = b.PartyID		
		INNER JOIN dbo.LA_InvoiceSetting i WITH (NOLOCK) ON i.ToPartyId = p.PartyID
		LEFT JOIN dbo.OAS_Party p1 WITH (NOLOCK) ON i.FromPartyId = p1.PartyID
		LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON i.InvTempId = temp.InvTemplateId
		LEFT JOIN dbo.LA_InvoiceType tp WITH (NOLOCK) ON i.InvTypeId = tp.InvTypeId
	WHERE p.PartyType = 4 
		AND (@BillerId = 0 OR i.ToPartyId = @BillerId)
		AND (@PayerId = 0 OR i.FromPartyId = @PayerId)
	GROUP BY i.ToPartyID, b.BillerName, i.FromPartyId, p1.PartyName, i.InvTypeId, tp.InvTypeName, i.InvTempId, temp.InvTemplateName
END			 	

GO
GRANT VIEW DEFINITION ON [dbo].[LA_InvoiceSettingSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_InvoiceSettingSel] TO bodbAdminNet 