USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_FunctionGroupSel]
	@FunctionId INT
AS
/*	Header:
	Created:2015.09.04 - Bravo.Tran
	Task :	Enhance Manage Function 
	DB:		DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.09.04: get function groups
*/
/*	Example:
	USE bodb_licensee
	EXEC [LA_FunctionGroupSel] 1
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT f.GroupID
	FROM dbo.LA_GroupFunction f		
	WHERE f.FunctionID = @FunctionId 		
END		

GO
GRANT EXECUTE ON [dbo].[LA_FunctionGroupSel] TO bodbAdminNet