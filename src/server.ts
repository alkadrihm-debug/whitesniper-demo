async function fetchData(url: string): Promise<any> {
  const response = await fetch(url);
  return response.json();
}

export async function startServer() {
  try {
    const data = await fetchData("https://api.example.com/data");
    console.log("Data:", data);
  } catch (error) {
    console.error("Error:", error);
  }
}
