/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_FunctionSelByGroup]
	@GroupID	 INT,
	@AdminID	 INT = 0
AS

/*  
	 Created: 20140814@Florent
	 Task : Select Function list by Group
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20140814@Florent: Initialize SP

	 Params :	 @AdminID: ID of User log on
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
		 INNER JOIN dbo.LA_GroupFunction gf WITH(NOLOCK) ON f.FunctionID = gf.FunctionID
		 INNER JOIN dbo.LA_UserFunction uf WITH(NOLOCK) ON f.FunctionID = uf.FunctionID
    WHERE gf.GroupID = @GroupID AND f.StatusID != 0
	     AND (@AdminID = 0 OR uf.UserID = @AdminID)
		  --AND (@getAll = 1 or f.StatusID != @getAll)
    GROUP BY f.FunctionID
		  ,FunctionName
		  ,FunctionDesc
		  ,ParentID
		  ,ParentName
		  ,URL
		  ,CreatedDate
		  ,ModifiedDate
		  ,DisplayOrder
		  ,Creator
		  ,f.StatusID
		  ,FunctionKey	
END
GO