USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_ProductListByPayerSel]
	 @PayerId	INT	= 0	
AS
/*  
	 Created: 20150413@Florent
	 Task : get List Products by Payerid or get all
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
		+ 0 get all products
		+ <> 0 all product by PayerID
	 Example:
		EXEC dbo.LA_ProductListByPayerSel 0
*/
BEGIN
	SET NOCOUNT ON	
	SELECT c.ProductID, pd.ProductPrefix, pd.ProductName
	FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON p.PartyID = c.FromParty
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeID = cs.ChargeID AND cs.SystemID = 2
		LEFT JOIN dbo.LA_f_Products3rd('') pd ON c.ProductID = pd.ProductID	
	WHERE (@PayerId = 0 OR p.PartyID = @PayerId)
	GROUP BY c.ProductID, pd.ProductPrefix, pd.ProductName
	
	
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_ProductListByPayerSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_ProductListByPayerSel] TO bodbAdminNet 