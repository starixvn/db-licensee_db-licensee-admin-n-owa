/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_FunctionSelByUser]
	@UserID	 INT
AS

/*  
	 Created: 20140814@Florent
	 Task : Select Function list by User
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20140814@Florent: Initialize SP

	 Params :	 @getAll : 0 : get only Function active
				    : 1 : get all function both active and not
*/
SET NOCOUNT ON

BEGIN
    SELECT	
		  f.FunctionID
		  ,FunctionName
		  ,FunctionDesc
		  ,ParentID
		  ,ParentName
		  ,URL
		  ,CreatedDate
		  ,ModifiedDate
		  ,DisplayOrder
		  ,Creator
		  ,f.StatusID AS IsActive
		  ,FunctionKey	
    FROM dbo.LA_Function f WITH(NOLOCK) 
		 INNER JOIN dbo.LA_UserFunction uf WITH(NOLOCK) ON f.FunctionID = uf.FunctionID
    WHERE uf.UserID = @UserID AND f.StatusID != 0
		  --AND (@getAll = 1 or f.StatusID != @getAll)
END
GO