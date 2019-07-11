/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_FunctionGroupSel]
	@FunctionId INT
AS
/*	Header:
	Created:2015.09.04 - Bravo.Tran
	Task :	Enhance Manage Function 
	DB:		DBCUST.bodb_Licensee
   
	Revisions: 
		+ 20150904@Bravo: get function groups
*/
/*	Example:
	USE bodb_licensee
	EXEC [LA_FunctionGroupSel] 1
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT f.GroupID
	FROM dbo.LA_GroupFunction f WITH (NOLOCK)
	WHERE f.FunctionID = @FunctionId 		
END		
GO