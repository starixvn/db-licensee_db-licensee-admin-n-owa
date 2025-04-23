/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPlay_ProductListSel]

AS
/*  
	Created: 20250319@Danny
	Task : Get all SabaPlay products
	DB: DBLIC.bodb_Licensee
	
	Revisions:     
		- 20250319@Danny: get List Product of SabaPlay

	EXEC SH_SabaPlay_ProductListSel
		
*/
BEGIN
	SET NOCOUNT ON

	SELECT ProductID, ProductName
	FROM bodb_licenseeReport.dbo.SabaPlay_Products WITH(NOLOCK)
	ORDER BY  ProductName

END
GO
