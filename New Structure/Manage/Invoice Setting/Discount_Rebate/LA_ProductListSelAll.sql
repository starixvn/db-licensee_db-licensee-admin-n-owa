USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_ProductListSelAll
AS
/*  
	 Created: 20150422@Patrick
	 Task : Get all products
	 DB: DB052.bodb_Licensee
	 Revisions:     
		
	 Params:
*/
BEGIN
	SET NOCOUNT ON
	SELECT ProductId, ProductName
	FROM dbo.LA_f_Products3rd('')
END
GO
GRANT VIEW DEFINITION ON dbo.LA_ProductListSelAll TO vnteam
GRANT EXECUTE ON dbo.LA_ProductListSelAll TO bodbAdminNet
GO