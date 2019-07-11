/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_FunctionGroupIns]
	@FunctionId INT,
	@GroupId	VARCHAR(50) ,
	@UserID		INT,
	@LoginIP	VARCHAR (50)	= '',
	@ErrCode	INT				= 0		OUTPUT,
	@ErrMsg		NVARCHAR(1000)	= ''	OUTPUT
AS
/*	Header:
	Created:2015.09.04 - Bravo.Tran
	Task :	Enhance Manage Function 
	DB:		DBCUST.bodb_Licensee
   
	Revisions: 
		- 20150904@Bravo: add function group
*/
/*	Example:
	USE bodb_licensee
	EXEC [LA_FunctionGroupIns] 1,1
*/
BEGIN
	SET NOCOUNT ON
	
	IF ISNULL(@FunctionId, 0) > 0
		AND ISNULL(@GroupId, '') != ''
	BEGIN
	
		DECLARE @Table TABLE (Id INT NOT NULL)	
		DECLARE @Delimiter CHAR(1)=','

		;WITH SeparatedTable (STARTVAL, STOPVAL) 
		AS 
		(
			SELECT
				STARTVAL = CAST(1 AS INT),
				STOPVAL = CHARINDEX(@Delimiter, @GroupId + @Delimiter) 
			UNION ALL SELECT
				STARTVAL = STOPVAL + 1,
				STOPVAL = CHARINDEX(@Delimiter, @GroupId + @Delimiter, STOPVAL + 1)
			FROM SeparatedTable
			WHERE STOPVAL > 0
		)
		INSERT @Table (Id)
		SELECT LTRIM(RTRIM(SUBSTRING(@GroupId, STARTVAL,	CASE
																WHEN STOPVAL > 0 THEN STOPVAL - STARTVAL
																ELSE 0
															END)))
		FROM SeparatedTable
		WHERE STOPVAL > 0
		OPTION (MAXRECURSION 0)
		
		DELETE FROM dbo.LA_GroupFunction WITH (ROWLOCK, UPDLOCK)
		WHERE FunctionID = @FunctionId
		
		INSERT INTO dbo.LA_GroupFunction(FunctionId, GroupID)
		SELECT @FunctionId, t.Id as GroupId
		FROM @Table t
		
		-- Write log ---------------------------------------------------------
		
		----------------------------------------------------------------------
		
		IF @@ERROR != 0
		BEGIN
			SELECT @ErrCode = 1, @ErrMsg = 'System Error. Insert failed!!!'
		END
	END
	ELSE
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Invalid Input. Insert failed!!!'
	END
END		
GO