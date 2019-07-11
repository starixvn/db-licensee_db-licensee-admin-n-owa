/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_InvoiceTypeListSel]
	 @InvoiceTypeId	INT	= 0	
AS
/*  
	 Created: 20150413@Florent
	 Task : get List Invoice type by all or id
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:     		  
		- 20180109@bruce: filter invoice type by IsVisible=1 [#87039]
	 Params:
		+ 0 get all Invoice type
		+ <> 0 specify a Invoice type
	 Example:
		EXEC dbo.LA_InvoiceTypeListSel 0
*/
SET NOCOUNT ON
BEGIN
	SELECT InvTypeId, InvTypeName
	FROM dbo.LA_InvoiceType WITH (NOLOCK)
	WHERE (@InvoiceTypeId = 0 OR InvTypeId = @InvoiceTypeId) AND IsVisible=1
END
GO